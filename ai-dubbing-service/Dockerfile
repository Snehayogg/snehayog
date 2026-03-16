# Base image with CUDA 11.8 for GPU support
FROM runpod/pytorch:2.1.0-py3.10-cuda11.8.0-devel-ubuntu22.04

# Update and install ffmpeg
RUN apt-get update && \
    apt-get install -y ffmpeg libsm6 libxext6 git && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Install standard Python requirements
COPY requirements.txt .
# Remove the local git reference for WhisperX from requirements for Docker
RUN sed -i '/whisperx/d' requirements.txt
RUN pip install --no-cache-dir -r requirements.txt

# Install WhisperX from git
RUN pip install --no-cache-dir git+https://github.com/m-bain/whisperx.git

# Copy server code
COPY main.py .

# Start RunPod Serverless Handler
CMD ["python", "-u", "main.py"]
