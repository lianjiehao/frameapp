# Reference-image fixture

`pose_person.png` is a centered, letterboxed 192×256 copy of
[TensorFlow.js pose-detection/pose.jpg](https://github.com/tensorflow/tfjs-models/blob/master/pose-detection/test_data/pose.jpg),
from the TensorFlow.js models repository under Apache-2.0 (see `TFJS-LICENSE`).
The source is 1000×667; fitting the whole photograph retains all limbs.

`test/reference_test.dart` uses this licensed photo to exercise reference-image
import, viewfinder overlays and UI screenshots. It is a test fixture, is not
shipped in the app, and is not evidence of pose detection or model accuracy.
The previous model output baseline is retired with the old pose detector.
