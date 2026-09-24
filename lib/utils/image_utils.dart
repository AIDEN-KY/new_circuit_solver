import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import 'error_handler.dart';

class PreparedImage {
  const PreparedImage({
    required this.filePath,
    required this.dataUri,
    required this.originalWidth,
    required this.originalHeight,
    required this.width,
    required this.height,
  });

  final String filePath;
  final String dataUri;
  final int originalWidth;
  final int originalHeight;
  final int width;
  final int height;
}

class ImageUtils {
  ImageUtils._();

  static const int maxUploadWidth = 1280;
  static const int jpegQuality = 80;

  static Future<PreparedImage> compressAndEncode(String sourcePath) async {
    try {
      final File source = File(sourcePath);
      if (!await source.exists()) {
        throw const AppException('图片文件不存在，请重新选择。');
      }
      final Uint8List bytes = await source.readAsBytes();
      if (bytes.isEmpty) throw const AppException('图片内容为空。');

      final Map<String, Object> result =
          await compute(_compressImageBytes, bytes);
      final Uint8List jpeg = result['bytes']! as Uint8List;
      final Directory temporaryDirectory = await getTemporaryDirectory();
      final String path =
          '${temporaryDirectory.path}${Platform.pathSeparator}circuit_solver_${DateTime.now().microsecondsSinceEpoch}.jpg';
      await File(path).writeAsBytes(jpeg, flush: true);

      return PreparedImage(
        filePath: path,
        dataUri: 'data:image/jpeg;base64,${base64Encode(jpeg)}',
        originalWidth: result['originalWidth']! as int,
        originalHeight: result['originalHeight']! as int,
        width: result['width']! as int,
        height: result['height']! as int,
      );
    } catch (error) {
      throw ErrorHandler.toAppException(error);
    }
  }
}

Map<String, Object> _compressImageBytes(Uint8List bytes) {
  final img.Image? decoded = img.decodeImage(bytes);
  if (decoded == null) throw const FormatException('无法解码图片');
  final img.Image oriented = img.bakeOrientation(decoded);
  final img.Image output = oriented.width > ImageUtils.maxUploadWidth
      ? img.copyResize(
          oriented,
          width: ImageUtils.maxUploadWidth,
          interpolation: img.Interpolation.linear,
        )
      : oriented;
  return <String, Object>{
    'bytes': Uint8List.fromList(
      img.encodeJpg(output, quality: ImageUtils.jpegQuality),
    ),
    'originalWidth': oriented.width,
    'originalHeight': oriented.height,
    'width': output.width,
    'height': output.height,
  };
}
