import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/ask_provider.dart';
import '../utils/error_handler.dart';
import 'loading_page.dart';

class CropPage extends StatefulWidget {
  const CropPage({required this.imagePath, super.key});

  final String imagePath;

  @override
  State<CropPage> createState() => _CropPageState();
}

class _CropPageState extends State<CropPage> {
  static const double _minimumSize = 0.15;
  Rect _selection = const Rect.fromLTWH(0.08, 0.08, 0.84, 0.84);
  Size? _imageSize;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSize();
  }

  Future<void> _loadSize() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final File file = File(widget.imagePath);
      if (!await file.exists()) throw const AppException('图片文件不存在。');
      final ImageStream stream = FileImage(file).resolve(ImageConfiguration.empty);
      late final ImageStreamListener listener;
      listener = ImageStreamListener(
        (ImageInfo info, bool synchronousCall) {
          stream.removeListener(listener);
          if (!mounted) return;
          setState(() {
            _imageSize = Size(
              info.image.width.toDouble(),
              info.image.height.toDouble(),
            );
            _loading = false;
          });
        },
        onError: (Object error, StackTrace? stackTrace) {
          stream.removeListener(listener);
          if (!mounted) return;
          setState(() {
            _loading = false;
            _error = '无法读取图片，请重新选择。';
          });
        },
      );
      stream.addListener(listener);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = ErrorHandler.messageFor(error);
      });
    }
  }

  void _move(DragUpdateDetails details, Size size) {
    final double dx = details.delta.dx / size.width;
    final double dy = details.delta.dy / size.height;
    setState(() {
      _selection = Rect.fromLTWH(
        (_selection.left + dx)
            .clamp(0.0, 1.0 - _selection.width)
            .toDouble(),
        (_selection.top + dy)
            .clamp(0.0, 1.0 - _selection.height)
            .toDouble(),
        _selection.width,
        _selection.height,
      );
    });
  }

  void _resize(
    DragUpdateDetails details,
    Size size,
    _ResizeHandle handle,
  ) {
    final double dx = details.delta.dx / size.width;
    final double dy = details.delta.dy / size.height;
    double left = _selection.left;
    double top = _selection.top;
    double right = _selection.right;
    double bottom = _selection.bottom;
    switch (handle) {
      case _ResizeHandle.topLeft:
        left = (left + dx).clamp(0.0, right - _minimumSize).toDouble();
        top = (top + dy).clamp(0.0, bottom - _minimumSize).toDouble();
        break;
      case _ResizeHandle.topRight:
        right = (right + dx).clamp(left + _minimumSize, 1.0).toDouble();
        top = (top + dy).clamp(0.0, bottom - _minimumSize).toDouble();
        break;
      case _ResizeHandle.bottomLeft:
        left = (left + dx).clamp(0.0, right - _minimumSize).toDouble();
        bottom =
            (bottom + dy).clamp(top + _minimumSize, 1.0).toDouble();
        break;
      case _ResizeHandle.bottomRight:
        right = (right + dx).clamp(left + _minimumSize, 1.0).toDouble();
        bottom =
            (bottom + dy).clamp(top + _minimumSize, 1.0).toDouble();
        break;
    }
    setState(() => _selection = Rect.fromLTRB(left, top, right, bottom));
  }

  Future<void> _confirm() async {
    final Size? imageSize = _imageSize;
    if (imageSize == null) return;
    context.read<AskProvider>().prepareQuestion(
      imagePath: widget.imagePath,
      cropBox: <String, num>{
        'x': (_selection.left * imageSize.width).round(),
        'y': (_selection.top * imageSize.height).round(),
        'w': (_selection.width * imageSize.width).round(),
        'h': (_selection.height * imageSize.height).round(),
      },
    );
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const LoadingPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('框选题目区域'),
        actions: <Widget>[
          IconButton(
            tooltip: '重置选框',
            onPressed: _imageSize == null
                ? null
                : () => setState(() => _selection =
                    const Rect.fromLTWH(0.08, 0.08, 0.84, 0.84)),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: <Widget>[
            const ColoredBox(
              color: Color(0xFFEFF6FF),
              child: Padding(
                padding: EdgeInsets.all(14),
                child: Row(
                  children: <Widget>[
                    Icon(Icons.touch_app_outlined, color: Color(0xFF2563EB)),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '拖动选框调整位置，拖动四个角调整大小。请完整框住题目条件。',
                        style: TextStyle(color: Color(0xFF1E40AF)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(child: _content()),
            Container(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
              ),
              child: ElevatedButton.icon(
                onPressed: _imageSize == null ? null : _confirm,
                icon: const Icon(Icons.auto_awesome_rounded),
                label: const Text('确认并开始识别'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _content() {
    if (_loading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('正在加载图片'),
          ],
        ),
      );
    }
    if (_error != null || _imageSize == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.broken_image_outlined, size: 58, color: Color(0xFFDC2626)),
              const SizedBox(height: 14),
              Text(_error ?? '无法显示图片', textAlign: TextAlign.center),
              const SizedBox(height: 18),
              OutlinedButton.icon(
                onPressed: _loadSize,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('重新加载'),
              ),
            ],
          ),
        ),
      );
    }
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final Size available = Size(constraints.maxWidth, constraints.maxHeight);
        final Rect imageRect = _containedRect(available, _imageSize!);
        return ColoredBox(
          color: const Color(0xFF0F172A),
          child: Stack(
            children: <Widget>[
              Positioned.fromRect(
                rect: imageRect,
                child: _selectableImage(imageRect.size),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _selectableImage(Size size) {
    final Rect rect = Rect.fromLTRB(
      _selection.left * size.width,
      _selection.top * size.height,
      _selection.right * size.width,
      _selection.bottom * size.height,
    );
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        Positioned.fill(child: Image.file(File(widget.imagePath), fit: BoxFit.fill)),
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(painter: _CropPainter(rect)),
          ),
        ),
        Positioned.fromRect(
          rect: rect,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onPanUpdate: (DragUpdateDetails details) => _move(details, size),
            child: Container(
              decoration: BoxDecoration(border: Border.all(color: Colors.white, width: 2)),
              alignment: Alignment.center,
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  color: Color(0x990F172A),
                  borderRadius: BorderRadius.all(Radius.circular(18)),
                ),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Text('拖动选框', style: TextStyle(color: Colors.white)),
                ),
              ),
            ),
          ),
        ),
        for (final _ResizeHandle handle in _ResizeHandle.values)
          _handle(handle, rect, size),
      ],
    );
  }

  Widget _handle(_ResizeHandle handle, Rect rect, Size size) {
    final Offset center = switch (handle) {
      _ResizeHandle.topLeft => rect.topLeft,
      _ResizeHandle.topRight => rect.topRight,
      _ResizeHandle.bottomLeft => rect.bottomLeft,
      _ResizeHandle.bottomRight => rect.bottomRight,
    };
    return Positioned(
      left: center.dx - 22,
      top: center.dy - 22,
      width: 44,
      height: 44,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: (DragUpdateDetails details) =>
            _resize(details, size, handle),
        child: Center(
          child: Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: const Color(0xFF2563EB),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
          ),
        ),
      ),
    );
  }

  Rect _containedRect(Size available, Size image) {
    final double scale = mathMin(available.width / image.width, available.height / image.height);
    final Size display = Size(image.width * scale, image.height * scale);
    return Offset(
          (available.width - display.width) / 2,
          (available.height - display.height) / 2,
        ) &
        display;
  }

  double mathMin(double a, double b) => a < b ? a : b;
}

enum _ResizeHandle { topLeft, topRight, bottomLeft, bottomRight }

class _CropPainter extends CustomPainter {
  const _CropPainter(this.selection);

  final Rect selection;

  @override
  void paint(Canvas canvas, Size size) {
    final Path overlay = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRect(selection);
    canvas.drawPath(overlay, Paint()..color = const Color(0x99000000));
    final Paint grid = Paint()
      ..color = const Color(0x88FFFFFF)
      ..strokeWidth = 1;
    for (int i = 1; i <= 2; i++) {
      final double x = selection.left + selection.width * i / 3;
      final double y = selection.top + selection.height * i / 3;
      canvas.drawLine(Offset(x, selection.top), Offset(x, selection.bottom), grid);
      canvas.drawLine(Offset(selection.left, y), Offset(selection.right, y), grid);
    }
  }

  @override
  bool shouldRepaint(_CropPainter oldDelegate) => oldDelegate.selection != selection;
}
