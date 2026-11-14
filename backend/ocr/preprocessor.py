"""
Image pre-processor using OpenCV and PIL.
Prepares scanned or photographed bus schedules for accurate OCR extraction.
"""

import os
import tempfile
import cv2
import numpy as np
from PIL import Image


def deskew(image: np.ndarray) -> np.ndarray:
    """Detect and correct text tilt/skew in the scanned image."""
    try:
        gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY) if len(image.shape) == 3 else image
        blur = cv2.GaussianBlur(gray, (9, 9), 0)
        thresh = cv2.threshold(blur, 0, 255, cv2.THRESH_BINARY_INV + cv2.THRESH_OTSU)[1]

        coords = np.column_stack(np.where(thresh > 0))
        if len(coords) < 10:
            return image

        angle = cv2.minAreaRect(coords)[-1]
        if angle < -45:
            angle = -(90 + angle)
        elif angle > 45:
            angle = 90 - angle
        else:
            angle = -angle

        # If angle is small or negligible, don't rotate
        if abs(angle) < 0.5 or abs(angle) > 45:
            return image

        (h, w) = image.shape[:2]
        center = (w // 2, h // 2)
        M = cv2.getRotationMatrix2D(center, angle, 1.0)
        rotated = cv2.warpAffine(image, M, (w, h), flags=cv2.INTER_CUBIC, borderMode=cv2.BORDER_REPLICATE)
        return rotated
    except Exception:
        return image


def preprocess_image(image_path: str) -> str:
    """
    Apply OpenCV preprocessing:
    1. Grayscale
    2. Noise reduction
    3. Contrast enhancement via CLAHE
    4. Deskewing
    Returns the path to the enhanced temporary image.
    """
    if not os.path.exists(image_path):
        raise FileNotFoundError(f"Image not found at {image_path}")

    # Read image
    img = cv2.imread(image_path)
    if img is None:
        # Fallback using PIL
        pil_img = Image.open(image_path).convert('RGB')
        img = np.array(pil_img)
        img = cv2.cvtColor(img, cv2.COLOR_RGB2BGR)

    # 1. Deskew
    img = deskew(img)

    # 2. Convert to Grayscale
    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)

    # 3. Apply CLAHE (Contrast Limited Adaptive Histogram Equalization)
    clahe = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(8, 8))
    contrast_enhanced = clahe.apply(gray)

    # 4. Bilateral filter to smooth noise while keeping text edges sharp
    filtered = cv2.bilateralFilter(contrast_enhanced, 9, 75, 75)

    # 5. Save preprocessed image to temporary file
    temp_dir = tempfile.gettempdir()
    preprocessed_path = os.path.join(temp_dir, f"klnce_preprocessed_{os.path.basename(image_path)}")
    cv2.imwrite(preprocessed_path, filtered)

    return preprocessed_path

