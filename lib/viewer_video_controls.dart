import 'package:flutter/material.dart';

/// Digital zoom and pan of the received WebRTC pixels only.
///
/// Screen orientation is handled by the viewer page, not by rotating pixels.
class ViewerVideoControls extends StatefulWidget {
  const ViewerVideoControls({super.key, required this.video});

  final Widget video;

  @override
  State<ViewerVideoControls> createState() => _ViewerVideoControlsState();
}

class _ViewerVideoControlsState extends State<ViewerVideoControls> {
  static const double _minZoom = 1;
  static const double _maxZoom = 4;

  final TransformationController _transformation = TransformationController();
  double _zoom = 1;

  @override
  void initState() {
    super.initState();
    _transformation.addListener(_updateZoomLabel);
  }

  void _updateZoomLabel() {
    if (!mounted) return;
    final next = _transformation.value
        .getMaxScaleOnAxis()
        .clamp(_minZoom, _maxZoom)
        .toDouble();
    if ((next - _zoom).abs() >= 0.01) {
      setState(() => _zoom = next);
    }
  }

  void _changeZoom(double factor, Size viewport) {
    final zoom = (_transformation.value.getMaxScaleOnAxis() * factor)
        .clamp(_minZoom, _maxZoom)
        .toDouble();
    final center = Offset(viewport.width / 2, viewport.height / 2);
    final sceneCenter = _transformation.toScene(center);
    _transformation.value = Matrix4.identity()
      ..translateByDouble(center.dx, center.dy, 0, 1)
      ..scaleByDouble(zoom, zoom, 1, 1)
      ..translateByDouble(-sceneCenter.dx, -sceneCenter.dy, 0, 1);
  }

  void _reset() {
    _transformation.value = Matrix4.identity();
  }

  @override
  void dispose() {
    _transformation.removeListener(_updateZoomLabel);
    _transformation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final viewport = constraints.biggest;
          return Stack(
            fit: StackFit.expand,
            children: [
              ClipRect(
                child: InteractiveViewer(
                  transformationController: _transformation,
                  minScale: _minZoom,
                  maxScale: _maxZoom,
                  panEnabled: true,
                  scaleEnabled: true,
                  child: SizedBox.expand(child: widget.video),
                ),
              ),
              Align(
                alignment: Alignment.bottomRight,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Material(
                    color: Colors.black.withValues(alpha: 0.76),
                    borderRadius: BorderRadius.circular(24),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(
                          tooltip: '축소',
                          onPressed: _zoom <= _minZoom + 0.01
                              ? null
                              : () => _changeZoom(1 / 1.5, viewport),
                          icon: const Icon(Icons.remove),
                        ),
                        Text('${_zoom.toStringAsFixed(1)}x'),
                        IconButton(
                          tooltip: '확대',
                          onPressed: _zoom >= _maxZoom - 0.01
                              ? null
                              : () => _changeZoom(1.5, viewport),
                          icon: const Icon(Icons.add),
                        ),
                        IconButton(
                          tooltip: '확대 초기화',
                          onPressed: _reset,
                          icon: const Icon(Icons.restart_alt),
                        ),
                      ]),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      );
}
