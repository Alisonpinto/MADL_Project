# HandTalk

HandTalk is a Flutter app that turns fingerspelled Auslan letters into on-screen text and spoken output. It uses the device camera, a Python inference service, and an optional language-model request to suggest a word from the captured letters.

## What It Does

- Streams camera frames to the configured Auslan inference server.
- Recognizes fingerspelled letters A-Z and filters predictions by confidence and a short cooldown.
- Builds a letter sequence, then can optionally ask OpenAI to suggest a word or phrase from it.
- Displays the captured text and can read it aloud using the device's text-to-speech engine.

The app is focused on fingerspelling; it does not translate full Auslan sentences or grammar.

## Requirements

- Flutter SDK with Dart 3.11.1 or later.
- Android Studio for Android builds, or Xcode on macOS for iOS builds.
- Python 3.10 recommended for the inference service.
- A camera-enabled device. A physical phone is recommended for camera testing.

## Quick Start

1. Clone the repository and enter the project directory:

	```sh
	git clone https://github.com/Alisonpinto/MADL_Project.git
	cd MADL_Project
	```

2. Install the Flutter dependencies and create a local environment file:

	```sh
	flutter pub get
	```

	Copy `.env.example` to `.env`. Set `AUSLAN_SERVER_URL` to the reachable URL of the inference service. For an Android emulator, use `http://10.0.2.2:8000/predict_auslan`; for a physical phone, use the development computer's LAN IP address. `OPENAI_API_KEY` is optional and only enables word/phrase suggestions.

3. Start the inference service from the repository root:

	```sh
	python -m venv .venv
	```

	Activate the environment, then install and run the server:

	```powershell
	.venv\Scripts\Activate.ps1
	pip install -r backend/requirements-auslan-server.txt
	uvicorn auslan_tflite_server:app --app-dir backend --host 0.0.0.0 --port 8000
	```

	On macOS or Linux, activate with `source .venv/bin/activate` instead. The server loads `assets/auslan_detection/model/auslan.tflite` relative to the repository root.

4. Run the app on a connected device or emulator:

	```sh
	flutter run
	```

Keep the server running while using camera recognition. The device and server must be able to reach one another over the network.

## Configuration

| Variable | Required | Purpose |
| --- | --- | --- |
| `AUSLAN_SERVER_URL` | Yes for camera recognition | Full inference endpoint, normally ending in `/predict_auslan`. |
| `OPENAI_API_KEY` | No | Enables optional word/phrase suggestions from the captured letters. |

Never commit `.env` or put a private API key in source control. The included `.env.example` contains placeholders only. Because this app bundles `.env` and makes the OpenAI request from the client, any key included in a distributed build can be extracted. Do not ship a private OpenAI key; production deployments should route word suggestions through a secured backend. Requests for optional word suggestions send the captured letters to the OpenAI API. Camera frames are sent to the inference server configured by `AUSLAN_SERVER_URL`.

## Backend Endpoints

- `GET /health` reports server and model-library status.
- `POST /predict_auslan` accepts an image upload and returns the predicted letter, confidence, and inference latency.

For local testing, check `http://127.0.0.1:8000/health` after starting the server. The app itself must use an address reachable from the device, not `127.0.0.1` unless the server is running on that same device.

## Project Layout

```text
lib/                          Flutter application and Auslan experience
  app/feature/auslan_scripts/  Prediction and camera integration
  app/screens/                 App screens
  app/services/                Speech output and shared services
assets/auslan_detection/      Auslan TFLite model
backend/                      FastAPI inference service
test/                          Flutter tests
```

## Development Checks

Run the Flutter analyzer and tests before submitting changes:

```sh
flutter analyze
flutter test
```

## Contributing

Open an issue to discuss larger changes, then submit a pull request with a concise description and the checks you ran. Keep credentials and generated build files out of commits.

## License

No license file is currently included. Contact the project maintainers before redistributing this project or its model assets.
