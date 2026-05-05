# AI Model Specifications - skeen v2

## Current Model
- **Filename:** `skeen_v2_quantized.tflite`
- **Format:** TFLite (Float16 Quantized)
- **Input Shape:** [1, 224, 224, 3]
- **Size:** ~7

## Model Overview
- **Core Architecture:** EfficientNetB0 (Fine-tuned)
- **Format:** TensorFlow Lite (.tflite)
- **Input Shape:** [1, 224, 224, 3]
- **Color Space:** RGB

## Classes & Target Labels
0. actinic_keratosis
1. bcc (Basal Cell Carcinoma)
2. melanoma
3. nevus (Benign)
4. scc (Squamous Cell Carcinoma)

## Pre-processing Requirements
- **Resizing:** Bilinear interpolation to 224x224.
- **Normalization:** The model includes an internal Rescaling layer (0-255 input expected). 
- **Inference Goal:** Prioritize Recall for SCC (Current: 0.77) and Melanoma.