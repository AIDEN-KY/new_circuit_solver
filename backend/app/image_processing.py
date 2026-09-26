from __future__ import annotations

import base64
import binascii
from io import BytesIO

from PIL import Image, ImageOps, UnidentifiedImageError

from .models import AskRequest


class InvalidImageError(ValueError):
    """客户端图片无法安全解码或裁剪。"""


class ImageProcessor:
    def __init__(self, max_image_bytes: int) -> None:
        self._max_image_bytes = max_image_bytes

    def prepare(self, request: AskRequest) -> bytes:
        raw = self.decode_data_uri(request.image_base64)
        image = self._open(raw)
        box = request.crop_box
        left = min(box.x, image.width)
        top = min(box.y, image.height)
        right = min(box.x + box.w, image.width)
        bottom = min(box.y + box.h, image.height)
        if right <= left or bottom <= top:
            raise InvalidImageError("框选区域超出图片范围")

        cropped = image.crop((left, top, right, bottom))
        if request.rotation_degrees:
            # Flutter 传入顺时针角度，Pillow 的正值为逆时针。
            cropped = cropped.rotate(-request.rotation_degrees, expand=True)
        output = BytesIO()
        cropped.save(output, format="JPEG", quality=90, optimize=True)
        return output.getvalue()

    def decode_data_uri(self, value: str) -> bytes:
        header, separator, encoded = value.partition(",")
        if not separator or not header.startswith("data:image/") or ";base64" not in header:
            raise InvalidImageError("image_base64 必须是图片 Data URI")
        try:
            raw = base64.b64decode(encoded, validate=True)
        except (binascii.Error, ValueError) as error:
            raise InvalidImageError("图片 Base64 数据无效") from error
        if not raw:
            raise InvalidImageError("图片内容为空")
        if len(raw) > self._max_image_bytes:
            raise InvalidImageError("图片体积超过服务端限制")
        return raw

    @staticmethod
    def fingerprint(image_bytes: bytes) -> int:
        image = ImageProcessor._open(image_bytes)
        grayscale = ImageOps.grayscale(image).resize((9, 8), Image.Resampling.LANCZOS)
        get_pixels = getattr(grayscale, "get_flattened_data", grayscale.getdata)
        pixels = list(get_pixels())
        value = 0
        for row in range(8):
            for column in range(8):
                left = pixels[row * 9 + column]
                right = pixels[row * 9 + column + 1]
                value = (value << 1) | int(left > right)
        return value

    @staticmethod
    def similarity(first: int, second: int) -> float:
        distance = (first ^ second).bit_count()
        return 1 - (distance / 64)

    @staticmethod
    def _open(image_bytes: bytes) -> Image.Image:
        try:
            image = Image.open(BytesIO(image_bytes))
            image.load()
            return ImageOps.exif_transpose(image).convert("RGB")
        except (UnidentifiedImageError, OSError, ValueError) as error:
            raise InvalidImageError("无法读取图片，请使用 JPEG 或 PNG 图片") from error
