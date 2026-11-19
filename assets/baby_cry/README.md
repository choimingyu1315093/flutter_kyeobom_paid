# YAMNet QA asset

Run `bash tools/prepare_baby_cry_model.sh` before building the cry QA flavor.
No model binary has been committed. The model is Google's float32 YAMNet audio classifier:
https://storage.googleapis.com/mediapipe-models/audio_classifier/yamnet/float32/latest/yamnet.tflite

The QA flag is OFF by default. Do not distribute a production build until the exact binary hash,
license/attribution, device compatibility, and classification quality have been reviewed.
