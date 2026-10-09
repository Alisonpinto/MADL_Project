from __future__ import annotations

import os
import time
from typing import Optional

import cv2
import mediapipe as mp
import numpy as np
import tensorflow as tf
from fastapi import FastAPI, File, UploadFile
from fastapi.responses import JSONResponse


MODEL_PATH = os.getenv(
    "AUSLAN_MODEL_PATH",
    "assets/auslan_detection/model/auslan.tflite",
)

labels_dict = {
    0: "A",
    1: "B",
    2: "C",
    3: "D",
    4: "E",
    5: "F",
    6: "G",
    7: "H",
    8: "I",
    9: "J",
    10: "K",
    11: "L",
    12: "M",
    13: "N",
    14: "O",
    15: "P",
    16: "Q",
    17: "R",
    18: "S",
    19: "T",
    20: "U",
    21: "V",
    22: "W",
    23: "X",
    24: "Y",
    25: "Z",
}

app = FastAPI()

interpreter = tf.lite.Interpreter(model_path=MODEL_PATH)
interpreter.allocate_tensors()
input_details = interpreter.get_input_details()
output_details = interpreter.get_output_details()

try:
    mp_hands = mp.solutions.hands
except AttributeError:
    from mediapipe.python import solutions as mp_solutions

    mp_hands = mp_solutions.hands

hands = mp_hands.Hands(
    static_image_mode=True,
    max_num_hands=2,
    min_detection_confidence=0.15,
)


def _extract_coords(frame_bgr: np.ndarray) -> Optional[list[float]]:
    # iPhone captures can be very large; resize for faster landmark extraction.
    h, w = frame_bgr.shape[:2]
    max_side = max(h, w)
    if max_side > 960:
        scale = 960.0 / max_side
        frame_bgr = cv2.resize(
            frame_bgr,
            (int(w * scale), int(h * scale)),
            interpolation=cv2.INTER_AREA,
        )

    # Android camera frames can arrive in sensor orientation. Try the native
    # frame plus both quarter-turn orientations before giving up.
    candidate_frames = (
        frame_bgr,
        cv2.rotate(frame_bgr, cv2.ROTATE_90_CLOCKWISE),
        cv2.rotate(frame_bgr, cv2.ROTATE_90_COUNTERCLOCKWISE),
    )
    results = None
    for candidate in candidate_frames:
        frame_rgb = cv2.cvtColor(candidate, cv2.COLOR_BGR2RGB)
        candidate_results = hands.process(frame_rgb)
        if candidate_results.multi_hand_landmarks:
            results = candidate_results
            break

    if results is None or not results.multi_hand_landmarks:
        return None

    x_all: list[float] = []
    y_all: list[float] = []
    coords = [0.0] * 126

    for hand_landmarks in results.multi_hand_landmarks:
        for lm in hand_landmarks.landmark:
            x_all.append(lm.x)
            y_all.append(lm.y)

    min_x = min(x_all)
    min_y = min(y_all)

    for hand_landmarks, handedness in zip(
        results.multi_hand_landmarks, results.multi_handedness
    ):
        label_hand = handedness.classification[0].label
        offset = 0 if label_hand == "Left" else 63
        i = offset
        for lm in hand_landmarks.landmark:
            coords[i] = lm.x - min_x
            coords[i + 1] = lm.y - min_y
            coords[i + 2] = lm.z
            i += 3

    return coords


@app.post("/predict_auslan")
async def predict_auslan(image: UploadFile = File(...)) -> JSONResponse:
    started = time.perf_counter()
    contents = await image.read()
    np_img = np.frombuffer(contents, np.uint8)
    frame = cv2.imdecode(np_img, cv2.IMREAD_COLOR)
    if frame is None:
        return JSONResponse({"label": None, "confidence": 0, "latency_ms": 0})

    coords = _extract_coords(frame)
    if coords is None:
        latency_ms = round((time.perf_counter() - started) * 1000, 1)
        print("Auslan: no hand detected", flush=True)
        return JSONResponse(
            {"label": None, "confidence": 0, "latency_ms": latency_ms}
        )

    input_data = np.array([coords], dtype=np.float32)
    interpreter.set_tensor(input_details[0]["index"], input_data)
    interpreter.invoke()
    output = interpreter.get_tensor(output_details[0]["index"])[0]

    # Ensure output is probabilities (softmax)
    if np.max(output) > 1.0 or np.min(output) < 0.0 or abs(np.sum(output) - 1.0) > 0.1:
        exp_vals = np.exp(output - np.max(output))
        output = exp_vals / np.sum(exp_vals)

    prediction_index = int(np.argmax(output))
    confidence = round(float(output[prediction_index]) * 100, 1)
    label = labels_dict[prediction_index]
    latency_ms = round((time.perf_counter() - started) * 1000, 1)
    print(
        f"Auslan: {label} confidence={confidence}% latency={latency_ms}ms",
        flush=True,
    )

    return JSONResponse(
        {"label": label, "confidence": confidence, "latency_ms": latency_ms}
    )


@app.get("/health")
def health() -> JSONResponse:
    return JSONResponse(
        {
            "ok": True,
            "mediapipe": getattr(mp, "__version__", "unknown"),
            "tensorflow": getattr(tf, "__version__", "unknown"),
        }
    )
