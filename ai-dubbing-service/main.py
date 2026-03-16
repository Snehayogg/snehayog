from fastapi import FastAPI, BackgroundTasks, HTTPException
from pydantic import BaseModel
import uvicorn
import requests
import os
import subprocess
import json
import uuid
import boto3
import torch
import gc
import shutil
from typing import Optional
from dotenv import load_dotenv

load_dotenv()

app = FastAPI(title="Vayug AI Dubbing Service")

class DubbingRequest(BaseModel):
    videoId: str
    videoUrl: str
    targetLanguage: str
    webhookUrl: str
    webhookSecret: str

# S3 / R2 Configuration
S3_ENDPOINT = os.getenv("R2_ENDPOINT_URL")
S3_ACCESS_KEY = os.getenv("AWS_ACCESS_KEY_ID")
S3_SECRET_KEY = os.getenv("AWS_SECRET_ACCESS_KEY")
S3_BUCKET = os.getenv("R2_BUCKET", "snehayog")
S3_PUBLIC_URL = os.getenv("R2_PUBLIC_URL", "https://pub.snehayog.com")

# LLM / Translation Configuration
OPENAI_API_KEY = os.getenv("OPENAI_API_KEY") # Shared for DeepSeek or Gemini
OPENAI_BASE_URL = os.getenv("OPENAI_BASE_URL", "https://api.deepseek.com")

# Global Model Cache
MODEL_CACHE = {
    "whisper": None,
    "tts": None,
    "device": "cuda" if torch.cuda.is_available() else "cpu"
}

print(f"--- Running on Device: {MODEL_CACHE['device']} ---")

def get_whisper_model():
    if MODEL_CACHE["whisper"] is None:
        import whisperx
        device = MODEL_CACHE["device"]
        compute_type = "float16" if device == "cuda" else "int8"
        print("Loading WhisperX model...")
        MODEL_CACHE["whisper"] = whisperx.load_model("large-v3", device, compute_type=compute_type)
    return MODEL_CACHE["whisper"]

def get_tts_model():
    if MODEL_CACHE["tts"] is None:
        from TTS.api import TTS
        device = MODEL_CACHE["device"]
        print("Loading Coqui XTTSv2 model...")
        MODEL_CACHE["tts"] = TTS("tts_models/multilingual/multi-dataset/xtts_v2").to(device)
    return MODEL_CACHE["tts"]

def translate_text(text: str, target_lang: str) -> str:
    """Translates text using DeepSeek or LLM API."""
    if not OPENAI_API_KEY:
        print("Warning: OPENAI_API_KEY not set. Using original text.")
        return text
        
    from openai import OpenAI
    client = OpenAI(api_key=OPENAI_API_KEY, base_url=OPENAI_BASE_URL)
    
    prompt = f"Translate the following video transcription to {target_lang}. Keep the same tone and context. Only return the translated text:\n\n{text}"
    
    try:
        response = client.chat.completions.create(
            model="deepseek-chat", # or gemini-1.5-flash
            messages=[{"role": "user", "content": prompt}],
            temperature=0.3
        )
        return response.choices[0].message.content
    except Exception as e:
        print(f"Translation failed: {e}")
        return text

def upload_to_r2(local_path: str, object_name: str) -> str:
    """Uploads a file to Cloudflare R2 and returns the public URL."""
    if not S3_ENDPOINT or not S3_ACCESS_KEY or not S3_SECRET_KEY:
        print("Warning: S3 credentials not configured. Skipping upload.")
        # Return a dummy URL for local testing if no credentials are provided
        return f"http://localhost:8000/temp/{object_name}"
        
    s3_client = boto3.client(
        's3',
        endpoint_url=S3_ENDPOINT,
        aws_access_key_id=S3_ACCESS_KEY,
        aws_secret_access_key=S3_SECRET_KEY,
        region_name="auto"
    )
    
    try:
        s3_client.upload_file(local_path, S3_BUCKET, object_name)
        public_url = f"{S3_PUBLIC_URL}/{object_name}"
        print(f"Uploaded successfully: {public_url}")
        return public_url
    except Exception as e:
        print(f"Failed to upload to R2: {e}")
        raise e

def _run_cmd(cmd: list):
    """Utility to run a shell command and print outputs."""
    print(f"Running: {' '.join(cmd)}")
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"Command failed: {result.stderr}")
        raise Exception(f"Command failed with code {result.returncode}")
    return result.stdout

def process_video_dubbing(req: DubbingRequest):
    """
    Background worker that handles the heavylifting for AI Dubbing.
    """
    print(f"Starting dubbing process for video {req.videoId} to {req.targetLanguage}")
    
    temp_dir = os.path.join(os.getcwd(), f"temp_{req.videoId}")
    os.makedirs(temp_dir, exist_ok=True)
    
    video_path = os.path.join(temp_dir, "input_video.mp4")
    audio_path = os.path.join(temp_dir, "input_audio.wav")
    voices_dir = os.path.join(temp_dir, "voices")
    
    try:
        # 1. Download Video
        print("1. Downloading video...")
        response = requests.get(req.videoUrl, stream=True)
        response.raise_for_status()
        with open(video_path, 'wb') as f:
            for chunk in response.iter_content(chunk_size=8192):
                f.write(chunk)
                
        # 2. Extract Audio
        print("2. Extracting audio...")
        _run_cmd(["ffmpeg", "-y", "-i", video_path, "-vn", "-acodec", "pcm_s16le", "-ar", "16000", "-ac", "1", audio_path])
        
        # 3. Separate Vocals (Demucs)
        print("3. Separating vocals using Demucs...")
        # We call Demucs as a process to manage VRAM better
        _run_cmd(["demucs", "-n", "htdemucs_ft", "-o", voices_dir, audio_path])
        
        # Determine path from Demucs naming convention
        base_name = os.path.splitext(os.path.basename(audio_path))[0]
        vocals_path = os.path.join(voices_dir, "htdemucs_ft", base_name, "vocals.wav")
        no_vocals_path = os.path.join(voices_dir, "htdemucs_ft", base_name, "no_vocals.wav")
        
        if not os.path.exists(vocals_path):
            raise Exception("Demucs failed to extract vocals.")

        # 4. Transcribe (WhisperX)
        print("4. Transcribing vocals with WhisperX...")
        model = get_whisper_model()
        import whisperx
        
        audio = whisperx.load_audio(vocals_path)
        result = model.transcribe(audio, batch_size=16)
        
        # Align timestamps
        model_a, metadata = whisperx.load_align_model(language_code=result["language"], device=MODEL_CACHE["device"])
        result = whisperx.align(result["segments"], model_a, metadata, audio, MODEL_CACHE["device"], return_char_alignments=False)
        
        full_text = " ".join([seg["text"] for seg in result["segments"]])
        print(f"Original Text: {full_text[:100]}...")

        # 5. Translate
        print(f"5. Translating text to {req.targetLanguage}...")
        translated_text = translate_text(full_text, req.targetLanguage)
        print(f"Translated Text: {translated_text[:100]}...")

        # 6. Generate TTS (XTTSv2)
        print("6. Generating cloned voice using XTTSv2...")
        tts = get_tts_model()
        generated_audio_path = os.path.join(temp_dir, "generated_vocals_raw.wav")
        
        tts.tts_to_file(
            text=translated_text,
            speaker_wav=vocals_path,
            language=req.targetLanguage if req.targetLanguage in ['en', 'hi', 'es', 'fr', 'de'] else 'hi',
            file_path=generated_audio_path
        )
        
        # 7. Speed Alignment (Matching original duration)
        print("7. Stretching audio to match original length...")
        final_vocals_path = os.path.join(temp_dir, "generated_vocals_aligned.wav")
        
        # Get durations
        import wave
        with wave.open(audio_path, 'r') as f:
            orig_duration = f.getnframes() / float(f.getframerate())
        with wave.open(generated_audio_path, 'r') as f:
            gen_duration = f.getnframes() / float(f.getframerate())
            
        rate = gen_duration / orig_duration
        # Use pyrubberband for high-quality time stretching without pitch shift
        _run_cmd(["ffmpeg", "-y", "-i", generated_audio_path, "-filter:a", f"atempo={rate}", final_vocals_path])
        
        # 8. Merge Audio
        print("8. Merging new vocals with background noise...")
        merged_audio_path = os.path.join(temp_dir, "merged_audio.wav")
        _run_cmd([
            "ffmpeg", "-y", 
            "-i", no_vocals_path, 
            "-i", final_vocals_path, 
            "-filter_complex", "amix=inputs=2:duration=longest:dropout_transition=0",
            merged_audio_path
        ])
        
        # 9. Merge Video & Audio
        print("9. Finalizing video...")
        final_video_name = f"final_dubbed_{req.targetLanguage}.mp4"
        final_video_path = os.path.join(temp_dir, final_video_name)
        _run_cmd([
            "ffmpeg", "-y",
            "-i", video_path,
            "-i", merged_audio_path,
            "-c:v", "copy",
            "-c:a", "aac",
            "-map", "0:v:0",
            "-map", "1:a:0",
            final_video_path
        ])
        
        # 10. Upload to R2
        print("10. Uploading to R2...")
        object_name = f"dubbed/{req.videoId}_{req.targetLanguage}_{uuid.uuid4().hex[:6]}.mp4"
        final_url = upload_to_r2(final_video_path, object_name)

        # 11. Webhook
        print("Dubbing finished successfully. Hitting webhook...")
        payload = {
            "videoId": req.videoId,
            "targetLanguage": req.targetLanguage,
            "status": "completed",
            "url": final_url,
            "webhookSecret": req.webhookSecret
        }
        requests.post(req.webhookUrl, json=payload, timeout=10)
        
    except Exception as e:
        print(f"Error dubbing video {req.videoId}: {e}")
        # Failure webhook payload
        payload = {
            "videoId": req.videoId,
            "status": "failed",
            "targetLanguage": req.targetLanguage,
            "error": str(e),
            "webhookSecret": req.webhookSecret
        }
        try:
             requests.post(req.webhookUrl, json=payload, timeout=10)
        except Exception:
             pass
             
    finally:
        # Crucial for GPU VRAM management
        if MODEL_CACHE["device"] == "cuda":
            torch.cuda.empty_cache()
            gc.collect()
        # Clean up temp files
        # shutil.rmtree(temp_dir, ignore_errors=True)
        print(f"Finished job {req.videoId}")


@app.post("/dubbing/start")
async def start_dubbing(req: DubbingRequest, background_tasks: BackgroundTasks):
    """
    Entrypoint for Node.js backend. 
    Accepts video info and immediately returns a 202 Accepted.
    The actual AI processing happens in the background.
    """
    
    background_tasks.add_task(process_video_dubbing, req)
    
    return {"message": "Dubbing job accepted", "jobId": f"job_{req.videoId}"}


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)
