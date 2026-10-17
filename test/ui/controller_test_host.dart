import 'package:flutter/widgets.dart';
import 'package:fruler/app/app_controller.dart';
import 'package:fruler/ui/fruler_app.dart';

/// Own the injected controller so background timers stop before widget invariants.
class ControllerTestHost extends StatefulWidget {
  const ControllerTestHost({super.key, required this.controller});
  final AppController controller;
  @override
  State<ControllerTestHost> createState() => _ControllerTestHostState();
}

class _ControllerTestHostState extends State<ControllerTestHost> {
  @override
  Widget build(BuildContext context) =>
      FrulerApp(controller: widget.controller);
  @override
  void dispose() {
    widget.controller.dispose();
    super.dispose();
  }
}
