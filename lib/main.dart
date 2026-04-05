import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─── Network Configuration ─────────────────────────────────────────────────
// Toggle this based on your testing environment:
//   • '127.0.0.1'     → iOS Simulator (localhost loopback)
//   • '10.0.2.2'      → Android Emulator (host machine alias)
//   • '192.168.x.x'   → Physical device on LAN
const String kDefaultHubIp = '192.168.63.86';
const int kHubPort = 8000;

// ─── ElevenLabs Configuration ──────────────────────────────────────────────
const String kElevenLabsBaseUrl = 'https://api.elevenlabs.io/v1';
const String kDefaultVoiceId = '21m00Tcm4TlvDq8ikWAM'; // Rachel
const String kDefaultModelId = 'eleven_multilingual_v2';

// ─── Theme Constants (Brutalist Boxy) ──────────────────────────────────────
const Color kScaffoldBlack = Color(0xFF111111);
const Color kAppBarGrey = Color(0xFF111111);
const Color kInputBarGrey = Color(0xFF111111);
const Color kThemeOrange = Color(0xFFFF4D00);
const Color kTextGreen = Color(0xFFFF4D00); // Reused for compatibility
const Color kTextWhite = Color(0xFFF9F9F9);
const Color kThemeWhite = Color(0xFFF9F9F9);
const Color kTextRed = Color(0xFFFF1744);
const Color kTextDimGreen = Color(0xFF8A2E00);
const Color kCursorGreen = Color(0xFFFF4D00);
const Color kTextAmber = Color(0xFFFFAB00);

// Brutalist Styles
const Color kBoxyShadowColor = Color(0xFFFF4D00);
const Color kBoxyBorderColor = Color(0x66FFFFFF);

const String kMonoFont = 'RobotoMono';

// ─── SharedPreferences Keys ────────────────────────────────────────────────
const String kPrefApiKey = 'elevenlabs_api_key';
const String kPrefTtsEnabled = 'tts_enabled';
const String kPrefHubIp = 'hub_ip';

void main() {
  runApp(const GhostOSApp());
}

class GhostOSApp extends StatelessWidget {
  const GhostOSApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ghost-OS Command Center',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: kScaffoldBlack,
        fontFamily: kMonoFont,
        colorScheme: const ColorScheme.dark(
          primary: kThemeOrange,
          surface: kScaffoldBlack,
        ),
      ),
      home: const SplashScreen(),
    );
  }
}

// ─── Splash Screen ─────────────────────────────────────────────────────────

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  // Ghost movement across the screen
  late AnimationController _ghostMoveController;
  late Animation<double> _ghostPosition;

  // Ghost mouth open/close (eating animation)
  late AnimationController _mouthController;

  // Ghost float/bob animation
  late AnimationController _floatController;

  // Fade out transition
  late AnimationController _fadeController;

  // Typing text
  String _displayText = '';
  int _textIndex = 0;
  Timer? _typingTimer;
  static const String _fullText = 'INITIALIZING GHOST-OS v4.2.1 ...';

  // Progress
  double _progress = 0.0;
  Timer? _progressTimer;

  // Dot positions (relative x: 0.0 to 1.0)
  final List<double> _dotPositions = [];
  final Set<int> _eatenDots = {};

  @override
  void initState() {
    super.initState();

    // Generate dot positions
    for (int i = 0; i < 20; i++) {
      _dotPositions.add(0.08 + (i * 0.045));
    }

    // Ghost moves from left to right
    _ghostMoveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4500),
    );
    _ghostPosition = Tween<double>(begin: -0.1, end: 1.1).animate(
      CurvedAnimation(parent: _ghostMoveController, curve: Curves.easeInOut),
    );
    _ghostMoveController.addListener(_checkDotCollisions);

    // Mouth chomp
    _mouthController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    )..repeat(reverse: true);

    // Float bob
    _floatController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    // Fade out
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    // Start sequence
    Future.delayed(const Duration(milliseconds: 400), () {
      _ghostMoveController.forward();
      _startTyping();
      _startProgress();
    });

    // Transition after animation
    _ghostMoveController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        Future.delayed(const Duration(milliseconds: 600), () {
          _fadeController.forward().then((_) {
            if (mounted) {
              Navigator.of(context).pushReplacement(
                PageRouteBuilder(
                  pageBuilder: (context, animation, secondaryAnimation) =>
                      const TerminalScreen(),
                  transitionsBuilder:
                      (context, animation, secondaryAnimation, child) {
                    return FadeTransition(opacity: animation, child: child);
                  },
                  transitionDuration: const Duration(milliseconds: 500),
                ),
              );
            }
          });
        });
      }
    });
  }

  void _checkDotCollisions() {
    final ghostX = _ghostPosition.value;
    for (int i = 0; i < _dotPositions.length; i++) {
      if (!_eatenDots.contains(i) && (ghostX - _dotPositions[i]).abs() < 0.025) {
        setState(() => _eatenDots.add(i));
      }
    }
  }

  void _startTyping() {
    _typingTimer = Timer.periodic(const Duration(milliseconds: 80), (timer) {
      if (_textIndex < _fullText.length) {
        setState(() {
          _displayText = _fullText.substring(0, _textIndex + 1);
          _textIndex++;
        });
      } else {
        timer.cancel();
      }
    });
  }

  void _startProgress() {
    _progressTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (_progress < 1.0) {
        setState(() {
          _progress += 0.012;
          if (_progress > 1.0) _progress = 1.0;
        });
      } else {
        timer.cancel();
      }
    });
  }

  @override
  void dispose() {
    _ghostMoveController.dispose();
    _mouthController.dispose();
    _floatController.dispose();
    _fadeController.dispose();
    _typingTimer?.cancel();
    _progressTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: kScaffoldBlack,
      body: AnimatedBuilder(
        animation: _fadeController,
        builder: (context, child) {
          return Opacity(
            opacity: 1.0 - _fadeController.value,
            child: child,
          );
        },
        child: Stack(
          children: [
            // ─── Scan-line grid background (Optimized)
            RepaintBoundary(
              child: CustomPaint(
                size: size,
                painter: _ScanLinePainter(),
              ),
            ),

            // ─── Main content
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 40),

                  // ─── Ghost eating dots arena
                  SizedBox(
                    width: size.width * 0.85,
                    height: 100,
                    child: AnimatedBuilder(
                      animation: Listenable.merge([
                        _ghostMoveController,
                        _mouthController,
                        _floatController,
                      ]),
                      builder: (context, _) {
                        return CustomPaint(
                          painter: _GhostArenaPainter(
                            ghostX: _ghostPosition.value,
                            mouthOpen: _mouthController.value,
                            floatOffset: _floatController.value,
                            dotPositions: _dotPositions,
                            eatenDots: _eatenDots,
                          ),
                        );
                      },
                    ),
                  ),

                  const SizedBox(height: 50),

                  // ─── GHOST-OS title
                  ShaderMask(
                    shaderCallback: (bounds) {
                      return LinearGradient(
                        colors: [
                          kThemeOrange,
                          kThemeWhite,
                          kThemeOrange,
                        ],
                      ).createShader(bounds);
                    },
                    child: const Text(
                      'GHOST-OS',
                      style: TextStyle(
                        fontFamily: kMonoFont,
                        fontSize: 36,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: 8,
                      ),
                    ),
                  ),

                  const SizedBox(height: 8),

                  Text(
                    'EDGE AI COMMAND CENTER',
                    style: TextStyle(
                      fontFamily: kMonoFont,
                      fontSize: 11,
                      color: kThemeOrange.withAlpha(120),
                      letterSpacing: 4,
                    ),
                  ),

                  const SizedBox(height: 40),

                  // ─── Typing text
                  SizedBox(
                    width: size.width * 0.8,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _displayText,
                          style: TextStyle(
                            fontFamily: kMonoFont,
                            fontSize: 12,
                            color: kThemeOrange.withAlpha(200),
                            letterSpacing: 1,
                          ),
                        ),
                        // Blinking cursor
                        AnimatedBuilder(
                          animation: _mouthController,
                          builder: (context, _) {
                            return Opacity(
                              opacity: _mouthController.value > 0.5 ? 1.0 : 0.0,
                              child: Text(
                                '█',
                                style: TextStyle(
                                  fontFamily: kMonoFont,
                                  fontSize: 12,
                                  color: kThemeOrange.withAlpha(200),
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // ─── Progress bar
                  SizedBox(
                    width: size.width * 0.6,
                    child: Column(
                      children: [
                        Container(
                          height: 3,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(2),
                            color: kThemeOrange.withAlpha(30),
                          ),
                          child: FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: _progress,
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(2),
                                color: kThemeOrange,
                                boxShadow: [
                                  BoxShadow(
                                    color: kThemeOrange.withAlpha(150),
                                    blurRadius: 8,
                                    spreadRadius: 1,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${(_progress * 100).toInt()}%',
                          style: TextStyle(
                            fontFamily: kMonoFont,
                            fontSize: 10,
                            color: kThemeOrange.withAlpha(100),
                            letterSpacing: 2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GhostArenaPainter extends CustomPainter {
  final double ghostX;
  final double mouthOpen;
  final double floatOffset;
  final List<double> dotPositions;
  final Set<int> eatenDots;

  _GhostArenaPainter({
    required this.ghostX,
    required this.mouthOpen,
    required this.floatOffset,
    required this.dotPositions,
    required this.eatenDots,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height / 2;
    final ghostSize = 38.0;

    // ─── Draw the subtle lane line
    final lanePaint = Paint()
      ..color = kThemeOrange.withAlpha(15)
      ..strokeWidth = 1.0;
    canvas.drawLine(
      Offset(0, centerY),
      Offset(size.width, centerY),
      lanePaint,
    );

    // ─── Draw dots
    for (int i = 0; i < dotPositions.length; i++) {
      final dotX = dotPositions[i] * size.width;
      
      if (eatenDots.contains(i)) {
        // Small lingering particle effect for eaten dots (optimized to just scale down)
        // Here we just skip rendering to keep it clean and performant,
        // but we could also paint a very faint small glow behind it.
        continue;
      }
      
      // Outer glow for un-eaten dots
      final dotPaint = Paint()
        ..color = kThemeOrange.withAlpha(150)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5);
      canvas.drawCircle(Offset(dotX, centerY), 4, dotPaint);
      
      // Inner bright core
      final innerPaint = Paint()..color = Colors.white.withAlpha(200);
      canvas.drawCircle(Offset(dotX, centerY), 1.5, innerPaint);
    }

    // ─── Ghost Coordinates
    final gx = ghostX * size.width;
    final bobOffset = (floatOffset - 0.5) * 8.0; // Smoother float
    final gy = centerY + bobOffset;

    // ─── Motion Trail
    final trailWidth = size.width * 0.15;
    final trailRect = Rect.fromLTRB(gx - trailWidth, gy - ghostSize * 0.4, gx, gy + ghostSize * 0.4);
    final trailGradient = LinearGradient(
      colors: [Colors.transparent, kThemeOrange.withAlpha(30)],
      stops: [0.0, 1.0],
    );
    final trailPaint = Paint()
      ..shader = trailGradient.createShader(trailRect)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawRRect(
      RRect.fromRectAndRadius(trailRect, const Radius.circular(20)),
      trailPaint,
    );

    // ─── Draw Ghost
    _drawPacGhost(canvas, gx, gy, ghostSize, mouthOpen);
  }

  void _drawPacGhost(Canvas canvas, double x, double y, double size, double mouth) {
    final halfSize = size / 2;

    // Outer glow for the ghost
    final glowPaint = Paint()
      ..color = kThemeOrange.withAlpha(80)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
    canvas.drawCircle(Offset(x, y), halfSize * 1.1, glowPaint);

    final left = x - halfSize;
    final right = x + halfSize;
    final top = y - halfSize;
    final bottom = y + halfSize * 0.9;

    // ─── Pac-Man Mouth Metrics
    // mouth goes from 0.0 (closed) to 1.0 (fully open)
    final mouthDepth = x - halfSize * 0.1;
    final mouthTop = y - halfSize * (mouth * 0.45);
    final mouthBottom = y + halfSize * (mouth * 0.45);

    // ─── Ghost Body Path
    final bodyPaint = Paint()
      ..color = kThemeOrange.withAlpha(230)
      ..style = PaintingStyle.fill;

    final path = Path();
    
    // Dome top
    path.moveTo(left, y);
    path.quadraticBezierTo(left, top, x, top);
    path.quadraticBezierTo(right, top, right, mouthTop);

    // Pac-man Mouth (right side)
    if (mouth > 0.05) {
      path.lineTo(mouthDepth, y);
      path.lineTo(right, mouthBottom);
    } else {
      path.lineTo(right, y);
    }

    // Wavy tentacle bottom
    final waveAmp = 4.0 + mouth * 2.5; 
    final tentacleCount = 3; 
    final tentacleWidth = (right - left) / tentacleCount;
    path.lineTo(right, bottom - waveAmp);
    
    for (int i = tentacleCount - 1; i >= 0; i--) {
      final tx = left + i * tentacleWidth;
      final midX = tx + tentacleWidth / 2;
      path.quadraticBezierTo(midX, bottom + waveAmp, tx, bottom - waveAmp);
    }

    path.close();
    canvas.drawPath(path, bodyPaint);

    // ─── Inner Gloss Highlight
    final highlightPaint = Paint()
      ..color = Colors.white.withAlpha(50)
      ..style = PaintingStyle.fill;
    final highlightPath = Path();
    highlightPath.moveTo(left + halfSize * 0.2, y - halfSize * 0.1);
    highlightPath.quadraticBezierTo(
      left + halfSize * 0.2, top + halfSize * 0.2,
      x, top + halfSize * 0.15,
    );
    highlightPath.quadraticBezierTo(
      left + halfSize * 0.5, top + halfSize * 0.5,
      left + halfSize * 0.2, y - halfSize * 0.1,
    );
    highlightPath.close();
    canvas.drawPath(highlightPath, highlightPaint);

    // ─── Eyes (Forward looking, focused)
    final eyeSize = size * 0.22;
    final eyeY = y - halfSize * 0.25;
    // Eye positions slightly pushed to the right to look determined
    final leftEyeX = x - halfSize * 0.15;
    final rightEyeX = x + halfSize * 0.45;

    // Skip drawing the right eye if the mouth is fully open and clipping it
    bool drawRightEye = mouth < 0.8;

    final eyeWhitePaint = Paint()..color = Colors.white.withAlpha(240);
    final pupilPaint = Paint()..color = kScaffoldBlack;
    final pupilHighlight = Paint()..color = kThemeOrange;

    void drawEye(double eX, double eY) {
      // White Base
      canvas.drawOval(
        Rect.fromCenter(center: Offset(eX, eY), width: eyeSize * 0.8, height: eyeSize),
        eyeWhitePaint,
      );
      // Pupil
      final pSize = eyeSize * 0.4;
      canvas.drawCircle(Offset(eX + 1.5, eY), pSize, pupilPaint);
      // Pupil Highlight
      canvas.drawCircle(Offset(eX + 2.5, eY - 1.5), 1.2, pupilHighlight);
    }

    drawEye(leftEyeX, eyeY);
    if (drawRightEye) {
      drawEye(rightEyeX, eyeY);
    }
  }

  @override
  bool shouldRepaint(covariant _GhostArenaPainter oldDelegate) {
    return ghostX != oldDelegate.ghostX ||
           mouthOpen != oldDelegate.mouthOpen ||
           floatOffset != oldDelegate.floatOffset ||
           eatenDots.length != oldDelegate.eatenDots.length;
  }
}

// ─── Scan Line Background Painter ─────────────────────────────────────

class _ScanLinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = kThemeOrange.withAlpha(8)
      ..strokeWidth = 0.5;

    // Horizontal scan lines
    for (double y = 0; y < size.height; y += 3) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
    }

    // Subtle grid dots
    final dotPaint = Paint()
      ..color = kThemeOrange.withAlpha(12);
    for (double x = 0; x < size.width; x += 30) {
      for (double y = 0; y < size.height; y += 30) {
        canvas.drawCircle(Offset(x, y), 0.5, dotPaint);
      }
    }

    // Vignette corners
    final vignetteGrad = RadialGradient(
      center: Alignment.center,
      radius: 0.9,
      colors: [
        Colors.transparent,
        Colors.black.withAlpha(120),
      ],
    );
    final vignettePaint = Paint()
      ..shader = vignetteGrad.createShader(
        Rect.fromLTWH(0, 0, size.width, size.height),
      );
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      vignettePaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class BoxyTerminalContainer extends StatelessWidget {
  final Widget child;
  
  const BoxyTerminalContainer({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF9F9F9), // Stark white just like the image's code block
        border: Border.all(color: const Color(0xFF111111), width: 3), // Rigid black border
        boxShadow: const [
          BoxShadow(
            color: kThemeOrange, // Giant orange solid shadow behind it
            offset: Offset(8, 8),
            blurRadius: 0,
            spreadRadius: 0,
          ),
        ],
      ),
      child: child,
    );
  }
}

// ─── Boxy / Brutalist UI Components ───────────────────────────────────────

class BoxyContainer extends StatelessWidget {
  final Widget child;
  final double borderRadius; // Kept for API compatibility, but ignored implicitly
  final EdgeInsetsGeometry padding;

  const BoxyContainer({
    super.key,
    required this.child,
    this.borderRadius = 0,
    this.padding = const EdgeInsets.all(16.0),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: kScaffoldBlack,
        border: Border.all(color: kBoxyBorderColor, width: 2),
        boxShadow: const [
          BoxShadow(
            color: kBoxyShadowColor,
            offset: Offset(6, 6),
            blurRadius: 0,
            spreadRadius: 0,
          ),
        ],
      ),
      child: child,
    );
  }
}

class BoxyInset extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final EdgeInsetsGeometry padding;

  const BoxyInset({
    super.key,
    required this.child,
    this.borderRadius = 0,
    this.padding = const EdgeInsets.all(16.0),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0A), // slightly darker physically inside
        border: Border.all(color: kBoxyBorderColor, width: 1.5),
      ),
      child: child,
    );
  }
}

class BoxyButton extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final double borderRadius;
  final EdgeInsetsGeometry padding;

  const BoxyButton({
    super.key,
    required this.child,
    required this.onTap,
    this.borderRadius = 0,
    this.padding = const EdgeInsets.all(12.0),
  });

  @override
  State<BoxyButton> createState() => _BoxyButtonState();
}

class _BoxyButtonState extends State<BoxyButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: widget.onTap,
      child: Transform.translate(
        // Move the whole button down and right physically on tap
        offset: _isPressed ? const Offset(4, 4) : Offset.zero,
        child: Container(
          padding: widget.padding,
          decoration: BoxDecoration(
            color: kScaffoldBlack,
            border: Border.all(color: kBoxyBorderColor, width: 2),
            boxShadow: _isPressed
                ? []
                : const [
                    BoxShadow(
                      color: kBoxyShadowColor,
                      offset: Offset(4, 4),
                      blurRadius: 0,
                      spreadRadius: 0,
                    ),
                  ],
          ),
          child: widget.child,
        ),
      ),
    );
  }
}


// ─── Terminal Screen ────────────────────────────────────────────────────────

class TerminalScreen extends StatefulWidget {
  const TerminalScreen({super.key});

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen>
    with TickerProviderStateMixin {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  final List<String> _logs = [];
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  bool _isConnected = false;
  bool _isConnecting = false;

  // Blinking cursor animation
  late AnimationController _cursorController;

  // ─── Voice Input (STT) ──────────────────────────────────────────────────
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isListening = false;
  bool _speechAvailable = false;
  late AnimationController _micPulseController;

  // ─── Network State ──────────────────────────────────────────────────────
  String _hubIp = kDefaultHubIp;

  // ─── Telemetry Data ─────────────────────────────────────────────────────
  Map<String, dynamic>? _systemMetrics;
  List<dynamic> _sensorMetrics = [];

  // ─── ElevenLabs TTS ─────────────────────────────────────────────────────
  final AudioPlayer _audioPlayer = AudioPlayer();
  final FlutterTts _flutterTts = FlutterTts();
  String? _elevenLabsApiKey;
  bool _ttsEnabled = true;
  bool _isSpeaking = false;

  // ─── TTS Batching (prevents 429 rate limit) ─────────────────────────────
  final List<String> _ttsBatchBuffer = [];
  Timer? _ttsBatchTimer;

  @override
  void initState() {
    super.initState();
    _cursorController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);

    _micPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    _initSpeech();
    _loadPreferences().then((_) => _connectToHub());
  }

  @override
  void dispose() {
    _cursorController.dispose();
    _micPulseController.dispose();
    _subscription?.cancel();
    _channel?.sink.close(status.goingAway);
    _ttsBatchTimer?.cancel();
    _inputController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  // ─── Preferences ──────────────────────────────────────────────────────

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _hubIp = prefs.getString(kPrefHubIp) ?? kDefaultHubIp;
      _elevenLabsApiKey = prefs.getString(kPrefApiKey);
      _ttsEnabled = prefs.getBool(kPrefTtsEnabled) ?? true;
    });
  }

  Future<void> _saveHubIp(String ip) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kPrefHubIp, ip);
    setState(() => _hubIp = ip);
    
    // Disconnect old and reconnect to new IP
    _subscription?.cancel();
    _channel?.sink.close();
    _connectToHub();
  }

  Future<void> _saveApiKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kPrefApiKey, key);
    setState(() => _elevenLabsApiKey = key);
  }

  Future<void> _clearApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(kPrefApiKey);
    setState(() => _elevenLabsApiKey = null);
  }

  Future<void> _toggleTts() async {
    final prefs = await SharedPreferences.getInstance();
    final newVal = !_ttsEnabled;
    await prefs.setBool(kPrefTtsEnabled, newVal);
    setState(() => _ttsEnabled = newVal);
  }

  // ─── Speech-to-Text ───────────────────────────────────────────────────

  Future<void> _initSpeech() async {
    _speechAvailable = await _speech.initialize(
      onError: (error) {
        setState(() => _isListening = false);
      },
      onStatus: (status) {
        if (status == 'notListening' || status == 'done') {
          setState(() => _isListening = false);
        }
      },
    );
  }

  void _toggleListening() {
    if (_isListening) {
      _stopListening();
    } else {
      _startListening();
    }
  }

  void _startListening() {
    if (!_speechAvailable) {
      setState(() {
        _logs.add('SYSTEM: [ERROR] Speech recognition not available on this device.');
      });
      _scrollToBottom();
      return;
    }

    setState(() => _isListening = true);

    _speech.listen(
      onResult: (result) {
        setState(() {
          _inputController.text = result.recognizedWords;
          _inputController.selection = TextSelection.fromPosition(
            TextPosition(offset: _inputController.text.length),
          );
        });
      },
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 3),
      listenOptions: stt.SpeechListenOptions(
        partialResults: true,
        cancelOnError: true,
      ),
    );
  }

  void _stopListening() {
    _speech.stop();
    setState(() => _isListening = false);
  }

  // ─── ElevenLabs TTS ───────────────────────────────────────────────────

  bool _shouldSkipTts(String text) {
    if (text.isEmpty) return true;
    if (text == 'SYSTEM_CLEAR_SIGNAL') return true;
    // Skip box-drawing lines and decorations
    if (RegExp(r'^[╔╗╚╝╠╣║═─│├└┌┐┘┤┬┴┼█░▓▒\s]+$').hasMatch(text)) return true;
    // Skip progress bars
    if (text.contains('████')) return true;
    return false;
  }

  String _cleanTextForTts(String text) {
    // Remove prefixes like SYSTEM:, [VISION], [GHOST-CLAW], etc.
    String cleaned = text
        .replaceAll(RegExp(r'^\[[\w-]+\]\s*'), '')
        .replaceAll(RegExp(r'^SYSTEM:\s*'), '')
        .replaceAll(RegExp(r'^>\s*'), '')
        .replaceAll(RegExp(r'[╔╗╚╝╠╣║═─│├└┌┐┘┤┬┴┼]'), '')
        .trim();
    return cleaned;
  }

  /// Queue a message for batched TTS. Waits 2s after the last message
  /// before sending everything as one combined API call.
  void _queueForTts(String text) {
    if (!_ttsEnabled) return;
    if (_shouldSkipTts(text)) return;

    final cleaned = _cleanTextForTts(text);
    if (cleaned.isEmpty) return;

    _ttsBatchBuffer.add(cleaned);

    // Reset the debounce timer — wait for more messages
    _ttsBatchTimer?.cancel();
    _ttsBatchTimer = Timer(const Duration(seconds: 2), _flushTtsBatch);
  }

  /// Flush all buffered lines into a single TTS API call.
  Future<void> _flushTtsBatch() async {
    if (_ttsBatchBuffer.isEmpty) return;

    // Grab and clear the buffer
    final combined = _ttsBatchBuffer.join('. ');
    _ttsBatchBuffer.clear();

    setState(() => _isSpeaking = true);

    try {
      bool usedElevenLabs = false;

      // Try ElevenLabs if API key exists
      if (_elevenLabsApiKey != null && _elevenLabsApiKey!.isNotEmpty) {
        try {
          final url = Uri.parse('$kElevenLabsBaseUrl/text-to-speech/$kDefaultVoiceId');
          
          final bodyPayload = jsonEncode({
            "text": combined,
            "model_id": kDefaultModelId,
            "voice_settings": {
              "stability": 0.5,
              "similarity_boost": 0.75
            }
          });

          final response = await http.post(
            url,
            headers: {
              'xi-api-key': _elevenLabsApiKey!,
              'Content-Type': 'application/json',
              'Accept': 'audio/mpeg',
            },
            body: bodyPayload,
          );

          if (response.statusCode == 200) {
            usedElevenLabs = true;
            final audioBytes = response.bodyBytes;
            // Write to temp file for reliable playback
            final tempDir = await Directory.systemTemp.createTemp('ghost_tts_');
            final tempFile = File('${tempDir.path}/tts_response.mp3');
            await tempFile.writeAsBytes(audioBytes);
            await _audioPlayer.setFilePath(tempFile.path);
            await _audioPlayer.play();
            // Clean up after playback
            try { await tempFile.delete(); await tempDir.delete(); } catch (_) {}
          } else {
            // Log ElevenLabs error (like 429 quota limit) but continue to Fallback
            setState(() {
              _logs.add('SYSTEM: [TTS] ElevenLabs error ${response.statusCode} - Falling back to native Voice');
            });
            _scrollToBottom();
          }
        } catch (elevenLabsError) {
          // If the network call itself completely fails (e.g., No Internet, SocketException),
          // log the failure so we fall through to the offline Native Voice fallback.
          setState(() {
             _logs.add('SYSTEM: [TTS] Network error with ElevenLabs - Falling back to native Voice');
          });
          _scrollToBottom();
        }
      }

      // Offline Fallback for empty API Key or ElevenLabs API Failures
      if (!usedElevenLabs) {
        await _flutterTts.setSpeechRate(0.5);
        await _flutterTts.setVolume(1.0);
        await _flutterTts.setPitch(1.0);
        await _flutterTts.awaitSpeakCompletion(true);
        await _flutterTts.speak(combined);
      }
      
    } catch (e) {
      if (!e.toString().contains('system tts')) {
        setState(() {
          _logs.add('SYSTEM: [TTS] Playback error — $e');
        });
        _scrollToBottom();
      }
    } finally {
      setState(() => _isSpeaking = false);
    }
  }

  Future<String> _testApiKey(String key) async {
    try {
      final url = Uri.parse('$kElevenLabsBaseUrl/voices');
      final response = await http.get(
        url,
        headers: {'xi-api-key': key},
      );
      if (response.statusCode == 200) {
        return 'valid';
      }
      return 'invalid';
    } catch (e) {
      if (e.toString().contains('SocketException')) {
        return 'network_error';
      }
      return 'invalid';
    }
  }

  // ─── WebSocket Connection ───────────────────────────────────────────────

  void _connectToHub() {
    if (_isConnecting) return;

    setState(() {
      _isConnecting = true;
      _logs.add('SYSTEM: Establishing uplink to $_hubIp:$kHubPort ...');
    });
    _scrollToBottom();

    try {
      final uri = Uri.parse('ws://$_hubIp:$kHubPort/ws');
      _channel = WebSocketChannel.connect(uri);

      _subscription = _channel!.stream.listen(
        _onMessage,
        onError: _onError,
        onDone: _onDisconnected,
        cancelOnError: false,
      );

      setState(() {
        _isConnected = true;
        _isConnecting = false;
      });
    } catch (e) {
      setState(() {
        _isConnecting = false;
        _logs.add('SYSTEM: [ERROR] Connection failed — $e');
      });
      _scrollToBottom();
    }
  }

  void _onMessage(dynamic message) {
    final raw = message.toString();
    String displayText;
    String msgType = '';

    // Real Ghost-OS sends JSON: { "type": "...", "payload": "...", ... }
    try {
      final Map<String, dynamic> parsed = jsonDecode(raw);
      final payload = parsed['payload'];
      msgType = (parsed['type'] ?? '').toString().toLowerCase();

      // Payload can be a string or a structured object
      if (payload is String) {
        displayText = payload;
      } else {
        displayText = jsonEncode(payload);
      }
    } catch (_) {
      // Fallback: mock server or plain text
      displayText = raw;
    }

    // Handle clear signal from either plain text or JSON payload
    if (displayText == 'SYSTEM_CLEAR_SIGNAL') {
      setState(() => _logs.clear());
      return;
    }

    // Skip internal JSON event payloads (e.g. fixcode_result, arduino_code)
    if (displayText.startsWith('{"event":')) return;

    // --- TELEMETRY INTERCEPTION ---
    if (msgType == 'status') {
      try {
        final payload = jsonDecode(raw)['payload'];
        if (payload is Map<String, dynamic>) {
          setState(() => _systemMetrics = payload);
          return; // Do NOT print to terminal
        }
      } catch (_) {}
    }
    
    if (msgType == 'sensor') {
      try {
        final payload = jsonDecode(raw)['payload'];
        if (payload is List<dynamic>) {
          setState(() => _sensorMetrics = payload);
          return; // Do NOT print to terminal
        }
      } catch (_) {}
    }

    setState(() => _logs.add(displayText));
    _scrollToBottom();

    // Queue for batched TTS (prevents 429 rate limit)
    _queueForTts(displayText);
  }

  void _onError(dynamic error) {
    setState(() {
      _isConnected = false;
      _logs.add('SYSTEM: [ERROR] WebSocket error — $error');
    });
    _scrollToBottom();
  }

  void _onDisconnected() {
    setState(() {
      _isConnected = false;
      _isConnecting = false;
      _logs.add('');
      _logs.add('SYSTEM: ╔═══════════════════════════════════════╗');
      _logs.add('SYSTEM: ║   Uplink severed. Connection lost.    ║');
      _logs.add('SYSTEM: ╚═══════════════════════════════════════╝');
      _logs.add('');
    });
    _scrollToBottom();
  }

  // ─── Send Command ──────────────────────────────────────────────────────

  void _sendCommand() {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;

    if (!_isConnected) {
      // Attempt reconnect if user types while disconnected
      if (text.toLowerCase() == 'reconnect') {
        _connectToHub();
        _inputController.clear();
        return;
      }
      setState(() {
        _logs.add('SYSTEM: [ERROR] Not connected. Type "reconnect" to retry.');
      });
      _scrollToBottom();
      _inputController.clear();
      return;
    }

    _channel?.sink.add(text);
    _inputController.clear();
    _focusNode.requestFocus();
  }

  // ─── Auto-Scroll ──────────────────────────────────────────────────────

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Color _getLogColor(String text) {
    if (text.startsWith('SYSTEM:')) return kThemeOrange;
    if (text.startsWith('>')) return const Color(0xFF111111); // Dark black for commands
    if (text.contains('error') || text.contains('ERROR')) return kTextRed;
    if (text.startsWith('//')) return const Color(0xFF777777); // Grey for comments
    return const Color(0xFF333333); // Dark slate grey for general output
  }

  IconData? _getLogIcon(String log) {
    if (log.startsWith('[DEAD-EYE]')) return Icons.warning_amber_rounded;
    if (log.startsWith('[GHOST-CLAW]')) return Icons.auto_awesome;
    if (log.startsWith('[VISION]')) return Icons.visibility;
    if (log.contains('[TTS]')) return Icons.volume_off;
    return null;
  }

  // ─── Telemetry Dashboard ──────────────────────────────────────────────

  Widget _buildStatCard(String title, String value, Color color) {
    return Expanded(
      child: BoxyInset(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Column(
          children: [
            Text(
              title,
              style: TextStyle(
                fontFamily: kMonoFont,
                fontSize: 9,
                fontWeight: FontWeight.bold,
                color: color.withAlpha(150),
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontFamily: kMonoFont,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: color,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTelemetryDashboard() {
    if (_systemMetrics == null && _sensorMetrics.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.speed, size: 12, color: kThemeOrange),
              const SizedBox(width: 6),
              Text(
                'SYSTEM TELEMETRY',
                style: TextStyle(
                  fontFamily: kMonoFont,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                  color: kThemeOrange.withAlpha(180),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_systemMetrics != null)
            Row(
              children: [
                _buildStatCard('CPU', '${_systemMetrics!["cpu_percent"]}%', kThemeOrange),
                const SizedBox(width: 8),
                _buildStatCard('RAM', '${_systemMetrics!["memory_percent"]}%', kThemeWhite),
                const SizedBox(width: 8),
                _buildStatCard('TMP', '${_systemMetrics!["temperature_c"] ?? "N/A"}°C', kTextAmber),
                const SizedBox(width: 8),
                _buildStatCard('DSK', '${_systemMetrics!["disk_percent"]}%', kTextWhite),
              ],
            ),
          if (_sensorMetrics.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              children: _sensorMetrics.take(4).map<Widget>((sensor) {
                final sType = (sensor['sensor_type'] ?? '').toString().toUpperCase();
                final String sVal = sensor['value']?.toString() ?? '0';
                final String sUnit = sensor['unit']?.toString() ?? '';
                return Padding(
                  padding: EdgeInsets.only(right: sensor == _sensorMetrics.take(4).last ? 0 : 8),
                  child: _buildStatCard(sType.length > 3 ? sType.substring(0, 3) : sType, '$sVal$sUnit', kThemeOrange),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  // ─── Settings Bottom Sheet ────────────────────────────────────────────

  void _showSettingsSheet() {
    final ipController = TextEditingController(text: _hubIp);
    final apiKeyController = TextEditingController(text: _elevenLabsApiKey ?? '');
    bool obscureKey = true;
    bool isTesting = false;
    String? testResult;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Container(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
              ),
              decoration: BoxDecoration(
                color: kScaffoldBlack,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: const [
                  BoxShadow(
                    color: kBoxyBorderColor,
                    blurRadius: 10,
                    offset: Offset(0, -4),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Handle bar
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: kThemeOrange.withAlpha(100),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    // ── Title
                    Row(
                      children: [
                        const Icon(Icons.settings, color: kThemeOrange, size: 20),
                        const SizedBox(width: 10),
                        const Text(
                          'SYSTEM SETTINGS',
                          style: TextStyle(
                            fontFamily: kMonoFont,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: kThemeOrange,
                            letterSpacing: 2,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Configure network and voice integrations',
                      style: TextStyle(
                        fontFamily: kMonoFont,
                        fontSize: 11,
                        color: kTextWhite.withAlpha(120),
                      ),
                    ),
                    const SizedBox(height: 24),
                    
                    // ── Hub IP field
                    Text(
                      'GHOST-OS HUB IP',
                      style: TextStyle(
                        fontFamily: kMonoFont,
                        fontSize: 11,
                        color: kThemeOrange.withAlpha(180),
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    BoxyInset(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: ipController,
                              style: const TextStyle(
                                fontFamily: kMonoFont,
                                fontSize: 13,
                                color: kTextWhite,
                              ),
                              cursorColor: kCursorGreen,
                              decoration: InputDecoration(
                                border: InputBorder.none,
                                hintText: 'e.g. 192.168.1.5',
                                hintStyle: TextStyle(
                                  fontFamily: kMonoFont,
                                  fontSize: 12,
                                  color: kTextWhite.withAlpha(40),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 12,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    
                    // ── Connect / Save IP button
                    BoxyButton(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      onTap: () async {
                        final ip = ipController.text.trim();
                        if (ip.isNotEmpty) {
                          await _saveHubIp(ip);
                          if (ctx.mounted) {
                            Navigator.pop(ctx);
                          }
                        }
                      },
                      child: const Center(
                        child: Text(
                          'CONNECT TO SYSTEM',
                          style: TextStyle(
                            fontFamily: kMonoFont,
                            fontSize: 12,
                            color: kThemeOrange,
                            letterSpacing: 1.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // ── API Key field

                    Text(
                      'ELEVENLABS API KEY',
                      style: TextStyle(
                        fontFamily: kMonoFont,
                        fontSize: 11,
                        color: kThemeOrange.withAlpha(180),
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    BoxyInset(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: apiKeyController,
                              obscureText: obscureKey,
                              style: const TextStyle(
                                fontFamily: kMonoFont,
                                fontSize: 13,
                                color: kTextWhite,
                              ),
                              cursorColor: kCursorGreen,
                              decoration: InputDecoration(
                                border: InputBorder.none,
                                hintText: 'Paste your API key here...',
                                hintStyle: TextStyle(
                                  fontFamily: kMonoFont,
                                  fontSize: 12,
                                  color: kTextWhite.withAlpha(40),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 12,
                                ),
                              ),
                            ),
                          ),
                          // Toggle visibility
                          GestureDetector(
                            onTap: () => setSheetState(() => obscureKey = !obscureKey),
                            child: Padding(
                              padding: const EdgeInsets.only(right: 14),
                              child: Icon(
                                obscureKey ? Icons.visibility_off : Icons.visibility,
                                color: kThemeOrange.withAlpha(120),
                                size: 20,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    // ── Action buttons
                    Row(
                      children: [
                        // Test button
                        Expanded(
                          child: BoxyButton(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            onTap: isTesting
                                ? () {}
                                : () async {
                                    final key = apiKeyController.text.trim();
                                    if (key.isEmpty) {
                                      setSheetState(() => testResult = 'No key entered');
                                      return;
                                    }
                                    setSheetState(() {
                                      isTesting = true;
                                      testResult = null;
                                    });
                                    final resultStatus = await _testApiKey(key);
                                    setSheetState(() {
                                      isTesting = false;
                                      if (resultStatus == 'valid') {
                                        testResult = '✓ Valid key';
                                      } else if (resultStatus == 'network_error') {
                                        testResult = '⚠ Network Error';
                                      } else {
                                        testResult = '✗ Invalid key';
                                      }
                                    });
                                  },
                            child: Center(
                              child: isTesting
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: kThemeOrange,
                                      ),
                                    )
                                  : Text(
                                      'TEST',
                                      style: TextStyle(
                                        fontFamily: kMonoFont,
                                        fontSize: 12,
                                        color: kThemeOrange.withAlpha(isTesting ? 100 : 255),
                                        letterSpacing: 1.5,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        // Save button
                        Expanded(
                          flex: 2,
                          child: BoxyButton(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            onTap: () async {
                              final key = apiKeyController.text.trim();
                              if (key.isNotEmpty) {
                                await _saveApiKey(key);
                                if (ctx.mounted) {
                                  Navigator.pop(ctx);
                                }
                                setState(() {
                                  _logs.add('SYSTEM: ElevenLabs API key saved. TTS enabled.');
                                });
                                _scrollToBottom();
                              }
                            },
                            child: const Center(
                              child: Text(
                                'SAVE KEY',
                                style: TextStyle(
                                  fontFamily: kMonoFont,
                                  fontSize: 12,
                                  color: kThemeOrange,
                                  letterSpacing: 1.5,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // ── Clear key button
                    if (_elevenLabsApiKey != null && _elevenLabsApiKey!.isNotEmpty)
                      BoxyButton(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        onTap: () async {
                          await _clearApiKey();
                          apiKeyController.clear();
                          if (ctx.mounted) {
                            Navigator.pop(ctx);
                          }
                          setState(() {
                            _logs.add('SYSTEM: ElevenLabs API key removed. TTS disabled.');
                          });
                          _scrollToBottom();
                        },
                        child: const Center(
                          child: Text(
                            'CLEAR KEY',
                            style: TextStyle(
                              fontFamily: kMonoFont,
                              fontSize: 12,
                              color: kTextRed,
                              letterSpacing: 1.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    // ── Test result feedback
                    if (testResult != null) ...[
                      const SizedBox(height: 12),
                      Center(
                        child: Text(
                          testResult!,
                          style: TextStyle(
                            fontFamily: kMonoFont,
                            fontSize: 12,
                            color: testResult!.startsWith('✓')
                                ? kThemeOrange
                                : kTextRed,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ─── Build ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final bool hasApiKey =
        _elevenLabsApiKey != null && _elevenLabsApiKey!.isNotEmpty;

    return Scaffold(
      backgroundColor: kScaffoldBlack,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(56),
        child: BoxyContainer(
          borderRadius: 0,
          padding: EdgeInsets.zero,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  // Status indicator
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _isConnected ? kThemeOrange : kTextRed,
                      boxShadow: [
                        BoxShadow(
                          color: (_isConnected ? kThemeOrange : kTextRed)
                              .withAlpha(153),
                          blurRadius: 8,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Responsive Title Group
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Row(
                        children: [
                          const Text(
                            'GHOST-OS',
                            style: TextStyle(
                              fontFamily: kMonoFont,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: kThemeOrange,
                              letterSpacing: 3,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _isConnected ? '• ONLINE' : '• OFFLINE',
                            style: TextStyle(
                              fontFamily: kMonoFont,
                              fontSize: 11,
                              color: _isConnected
                                  ? kThemeOrange.withAlpha(178)
                                  : kTextRed.withAlpha(178),
                              letterSpacing: 2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  // TTS mute/unmute toggle (with speaking indicator)
                  if (hasApiKey)
                    GestureDetector(
                      onTap: _toggleTts,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Icon(
                          _isSpeaking
                              ? Icons.graphic_eq_rounded
                              : (_ttsEnabled
                                  ? Icons.volume_up_rounded
                                  : Icons.volume_off_rounded),
                          color: _isSpeaking
                              ? kThemeWhite
                              : (_ttsEnabled
                                  ? kThemeOrange
                                  : kThemeOrange.withAlpha(80)),
                          size: 22,
                        ),
                      ),
                    ),
                  // Settings button
                  GestureDetector(
                    onTap: _showSettingsSheet,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Icon(
                        Icons.settings_rounded,
                        color: hasApiKey ? kThemeOrange : kThemeOrange.withAlpha(120),
                        size: 22,
                      ),
                    ),
                  ),
                  // Reconnect button
                  if (!_isConnected)
                    GestureDetector(
                      onTap: _connectToHub,
                      child: Container(
                        margin: const EdgeInsets.only(left: 6),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(color: kThemeOrange, width: 1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'RECONNECT',
                          style: TextStyle(
                            fontFamily: kMonoFont,
                            fontSize: 10,
                            color: kThemeOrange,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          // ─── Live Telemetry Dashboard ──────────────────────────────
          _buildTelemetryDashboard(),

          // ─── Terminal Log Area ─────────────────────────────────────
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
              child: BoxyTerminalContainer(
                child: _logs.isEmpty
                    ? Center(
                        child: AnimatedBuilder(
                          animation: _cursorController,
                          builder: (context, child) {
                            return Opacity(
                              opacity: _cursorController.value,
                              child: const Text(
                                '█',
                                style: TextStyle(
                                  fontFamily: kMonoFont,
                                  fontSize: 24,
                                  color: kThemeOrange,
                                ),
                              ),
                            );
                          },
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                        itemCount: _logs.length,
                        itemBuilder: (context, index) {
                          final log = _logs[index];
                          if (log.isEmpty) return const SizedBox(height: 8);

                          final color = _getLogColor(log);
                          final icon = _getLogIcon(log);

                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4.0),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (icon != null) ...[
                                  Icon(icon, size: 14, color: color),
                                  const SizedBox(width: 8),
                                ],
                                Expanded(
                                  child: Text(
                                    log,
                                    style: TextStyle(
                                      fontFamily: kMonoFont,
                                      fontSize: 14, // Slightly larger for readability on white
                                      color: color,
                                      height: 1.6,
                                      fontWeight: log.startsWith('>') ? FontWeight.bold : FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ),
          ),

          // ─── Input Bar ────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  // Text field
                  Expanded(
                    child: BoxyInset(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: Row(
                        children: [
                          const Text(
                            '>\$ ',
                            style: TextStyle(
                              fontFamily: kMonoFont,
                              fontSize: 15,
                              color: kThemeOrange,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Expanded(
                            child: TextField(
                              controller: _inputController,
                              focusNode: _focusNode,
                              style: const TextStyle(
                                fontFamily: kMonoFont,
                                fontSize: 14,
                                color: kTextWhite,
                              ),
                              cursorColor: kCursorGreen,
                              decoration: InputDecoration(
                                border: InputBorder.none,
                                hintText: _isListening
                                    ? 'Listening...'
                                    : 'Enter command ...',
                                hintStyle: TextStyle(
                                  fontFamily: kMonoFont,
                                  fontSize: 13,
                                  color: _isListening
                                      ? kThemeOrange.withAlpha(150)
                                      : const Color(0xFF666666),
                                ),
                                isDense: true,
                              ),
                              onSubmitted: (_) => _sendCommand(),
                              textInputAction: TextInputAction.send,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  
                  // Mic button
                  AnimatedBuilder(
                    animation: _micPulseController,
                    builder: (context, child) {
                      final double glowOpacity = _isListening
                          ? 0.3 + (_micPulseController.value * 0.5)
                          : 0.0;
                      return Container(
                        decoration: _isListening
                            ? BoxDecoration(
                                boxShadow: [
                                  BoxShadow(
                                    color: kThemeOrange.withAlpha((glowOpacity * 200).toInt()),
                                    blurRadius: 12,
                                    spreadRadius: 2,
                                  ),
                                ],
                                borderRadius: BorderRadius.circular(12),
                              )
                            : null,
                        child: BoxyButton(
                          onTap: _toggleListening,
                          padding: const EdgeInsets.all(12),
                          child: Icon(
                            _isListening ? Icons.mic : Icons.mic_none_rounded,
                            color: _isListening ? kThemeOrange : kTextWhite.withAlpha(180),
                            size: 22,
                          ),
                        ),
                      );
                    },
                  ),
                  
                  const SizedBox(width: 12),
                  
                  // Send button
                  BoxyButton(
                    onTap: _sendCommand,
                    padding: const EdgeInsets.all(12),
                    child: const Icon(
                      Icons.send_rounded,
                      color: kThemeOrange,
                      size: 22,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
