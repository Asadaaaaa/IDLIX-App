import 'package:flutter/material.dart';

class IdlixSplashScreen extends StatefulWidget {
  final int loadingProgress;
  final bool isFinished;
  final VoidCallback? onDismissed;

  const IdlixSplashScreen({
    super.key,
    required this.loadingProgress,
    required this.isFinished,
    this.onDismissed,
  });

  @override
  State<IdlixSplashScreen> createState() => _IdlixSplashScreenState();
}

class _IdlixSplashScreenState extends State<IdlixSplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  bool _canDismiss = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    // Simple, clean, elegant fade and subtle zoom
    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeIn,
    );

    _scaleAnimation = Tween<double>(begin: 0.92, end: 1.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: Curves.easeOutCubic,
      ),
    );

    _animController.forward().then((_) {
      if (mounted) {
        setState(() {
          _canDismiss = true;
        });
        if (widget.isFinished) {
          widget.onDismissed?.call();
        }
      }
    });
  }

  @override
  void didUpdateWidget(covariant IdlixSplashScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isFinished && _canDismiss && !oldWidget.isFinished) {
      widget.onDismissed?.call();
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Pure fullscreen black background
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: Colors.black,
      child: AnimatedBuilder(
        animation: _animController,
        builder: (context, _) {
          return FadeTransition(
            opacity: _fadeAnimation,
            child: ScaleTransition(
              scale: _scaleAnimation,
              child: Stack(
                children: [
                  // Center Clean IDLIX Logo & Title
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Clean IDLIX Emblem
                        Container(
                          width: 84,
                          height: 84,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE50914),
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFE50914).withValues(alpha: 0.3),
                                blurRadius: 18,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: const Center(
                            child: Icon(
                              Icons.play_arrow_rounded,
                              color: Colors.white,
                              size: 56,
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Title
                        const Text(
                          'IDLIX',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 34,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 4.0,
                          ),
                        ),
                        const SizedBox(height: 6),

                        // Subtitle in English
                        const Text(
                          'STREAMING CINEMA',
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 2.5,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Minimalist Bottom Progress Bar
                  Positioned(
                    left: 48,
                    right: 48,
                    bottom: 48,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            value: widget.loadingProgress > 0
                                ? (widget.loadingProgress / 100).clamp(0.05, 1.0)
                                : null,
                            backgroundColor: Colors.white12,
                            valueColor: const AlwaysStoppedAnimation<Color>(
                              Color(0xFFE50914),
                            ),
                            minHeight: 2.5,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          widget.loadingProgress > 0
                              ? 'Connecting to IDLIX (${widget.loadingProgress}%)...'
                              : 'Connecting to IDLIX...',
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 11,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
