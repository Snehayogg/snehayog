import runpod
import os
from main import process_video_dubbing, DubbingRequest

def handler(job):
    """
    RunPod Serverless Handler.
    The 'job' object contains 'input', which will have our dubbing parameters.
    """
    job_input = job["input"]
    
    # Map job input to our DubbingRequest structure
    try:
        req = DubbingRequest(
            videoId=job_input.get("videoId"),
            videoUrl=job_input.get("videoUrl"),
            targetLanguage=job_input.get("targetLanguage"),
            webhookUrl=job_input.get("webhookUrl"),
            webhookSecret=job_input.get("webhookSecret")
        )
        
        # Execute the main AI processing logic
        # Since process_video_dubbing handles its own errors and webhooks,
        # we can just call it directly.
        process_video_dubbing(req)
        
        return {"status": "success", "videoId": req.videoId}
    except Exception as e:
        return {"status": "error", "error": str(e)}

if __name__ == "__main__":
    print("--- Starting RunPod Serverless Worker ---")
    runpod.serverless.start({"handler": handler})
