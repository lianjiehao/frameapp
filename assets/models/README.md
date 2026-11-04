# Bundled body landmark model / 内置人体关键点模型

MoveNet SinglePose Lightning, TensorFlow Lite float16 v1 (file 4.tflite), from [Google on Kaggle](https://www.kaggle.com/models/google/movenet/tfLite/singlepose-lightning-tflite-float16/1). [Apache-2.0 license](LICENSE).

SHA-256: `0fac2226112d0371903ca86e3853cec24ef603a0b2f96f589b180f0ebdd135ab`.

Input: uint8 [1,192,192,3]. Output: float32 [1,1,17,3], ordered y/x/confidence. Android uses LiteRT 1.4.0 on a serial CPU worker. The 192×256 preview fits inside the square tensor with symmetric horizontal padding; output coordinates are transformed back before comparison. iOS uses system Vision instead.

模型在 Android 本机离线推理，无运行时下载、图像上传或身份识别。单人模型可能选择画面中主要人物，不保证多人身份跟踪；输出用于重合提示，不是动作或审美评分。
