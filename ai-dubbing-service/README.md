# Snehayog AI Dubbing Service

This is the Python microservice responsible for doing the heavy lifting of AI Video Dubbing.

## Prerequisites
- A system with an Nvidia GPU (12GB+ VRAM recommended)
- CUDA 11.8+
- Python 3.10+
- FFmpeg installed (`sudo apt install ffmpeg` or via Chocolately on Windows)

## Installation

```bash
pip install -r requirements.txt
```

Note: Installing `TTS` and `whisperx` natively on Windows can be tricky due to pure C++ dependencies. Using WSL2 or Docker is highly recommended.

## Running the Server

```bash
uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

## Deployment Recommendations
Since loading models like XTTS and Whisper takes 5-10 seconds, and VRAM is expensive, we recommend deploying this on a Serverless GPU platform like **RunPod Serverless** or **Modal.com**.

The `main.py` scaffolding manages the lifecycle of the webhook to communicate back to the Node.js backend.

## Environment Variables
Create a `.env` file with the following keys if utilizing R2/S3 integration:
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `R2_ENDPOINT_URL`
