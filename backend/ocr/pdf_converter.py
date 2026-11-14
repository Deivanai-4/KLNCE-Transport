"""
PDF to Image converter utility using pdf2image.
Extracts individual pages from uploaded schedule PDFs for OCR processing.
"""

import os
import tempfile
from typing import List


def pdf_to_images(pdf_path: str, output_dir: str = None, dpi: int = 300) -> List[str]:
    """
    Converts each page of a PDF file into high-resolution PNG image.
    Returns a list of absolute file paths to the generated images.
    """
    if not os.path.exists(pdf_path):
        raise FileNotFoundError(f"PDF file not found at: {pdf_path}")

    if output_dir is None:
        output_dir = tempfile.gettempdir()
    os.makedirs(output_dir, exist_ok=True)

    image_paths = []
    try:
        from pdf2image import convert_from_path
        pages = convert_from_path(pdf_path, dpi=dpi)
        base_name = os.path.splitext(os.path.basename(pdf_path))[0]

        for i, page in enumerate(pages):
            out_file = os.path.join(output_dir, f"{base_name}_page_{i + 1}.png")
            page.save(out_file, 'PNG')
            image_paths.append(out_file)

        return image_paths
    except ImportError:
        raise RuntimeError("pdf2image library is required to process PDF schedules. Install poppler and pdf2image.")
    except Exception as exc:
        raise RuntimeError(f"Failed to convert PDF to images: {str(exc)}")

