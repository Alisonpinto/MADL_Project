FROM python:3.10-slim

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

WORKDIR /app

# Runtime libs required by OpenCV/MediaPipe.
RUN apt-get update && apt-get install -y --no-install-recommends \
    libglib2.0-0 \
    libgl1 \
    libsm6 \
    libxext6 \
    libxrender1 \
    && rm -rf /var/lib/apt/lists/*

COPY backend/requirements-auslan-server.txt /app/backend/requirements-auslan-server.txt
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -r /app/backend/requirements-auslan-server.txt

# Copy backend code and model assets into the image.
COPY backend /app/backend
COPY assets /app/assets

EXPOSE 10000

CMD ["sh", "-c", "uvicorn backend.auslan_tflite_server:app --host 0.0.0.0 --port ${PORT:-10000}"]
