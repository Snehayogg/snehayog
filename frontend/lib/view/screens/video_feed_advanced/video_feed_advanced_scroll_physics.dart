part of 'package:vayu/view/screens/video_feed_advanced.dart';

class VayuScrollPhysics extends ScrollPhysics {
  const VayuScrollPhysics({super.parent});

  @override
  VayuScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return VayuScrollPhysics(parent: buildParent(ancestor));
  }

  @override
  Simulation? createBallisticSimulation(
      ScrollMetrics position, double velocity) {
    // If we're out of range and not stationary, defer to parent (overscroll)
    if ((velocity < 0.0 && position.pixels <= position.minScrollExtent) ||
        (velocity > 0.0 && position.pixels >= position.maxScrollExtent)) {
      return super.createBallisticSimulation(position, velocity);
    }

    final Tolerance tolerance = this.tolerance;
    final double target = _getTargetPixels(position, velocity, tolerance);

    if (target != position.pixels) {
      return ScrollSpringSimulation(
        spring,
        position.pixels,
        target,
        velocity,
        tolerance: tolerance,
      );
    }
    return null;
  }

  @override
  bool get allowImplicitScrolling => false;

  double _getTargetPixels(
      ScrollMetrics position, double velocity, Tolerance tolerance) {
    double page = position.pixels / position.viewportDimension;
    double remaining = page % 1;
    int currentPage = page.floor();

    double targetPage = currentPage.toDouble();

    // Custom Velocity Threshold (Sensitive - lowered from 100.0)
    const double velocityThreshold = 20.0;

    // Custom Swipe Threshold (12% - lowered from 15%)
    const double swipeThreshold = 0.12;

    // 1. Velocity Check (Fast Swipe)
    if (velocity.abs() > velocityThreshold) {
      if (velocity > 0) {
        // Velocity > 0 means pixels increasing = Next Video
        targetPage = (currentPage + 1).toDouble();
      } else {
        // Velocity < 0 means pixels decreasing = Previous Video (Stay at current or go back)
        // If we are partly into next video but swipe back up, we want to snap back to current (which is floor).
        // If we were at current and swipe up (velocity > 0), we go to next.
        // If we swipe down (velocity < 0), we go to previous?
        // Wait, standard behavior:
        // Position 0 -> 1.
        // If at 0.1 and swipe UP (finger up, content down, velocity < 0? No.)
        // Finger UP = Dragging content UP = Pixels Increasing = Velocity > 0.
        // Finger DOWN = Dragging content DOWN = Pixels Decreasing = Velocity < 0.

        // So Velocity > 0 => Next.
        // Velocity < 0 => Previous.
        targetPage = currentPage.toDouble();
      }
    } else {
      // 2. Distance Check (Slow Swipe)
      // If we dragged more than 15% past the current page, go to next.
      if (remaining > swipeThreshold) {
        targetPage = (currentPage + 1).toDouble();
      } else {
        targetPage = currentPage.toDouble();
      }
    }

    // Since we are snapping, we usually want to snap to integer pages.
    return targetPage * position.viewportDimension;
  }
}
