import 'dart:io';
import 'dart:math' show pi, cos, sin;  // Add math imports for SunRaysPainter
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_ml_kit/google_ml_kit.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibration/vibration.dart';
import 'package:translator/translator.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:provider/provider.dart';
import 'package:flutter/widgets.dart';

class FadePageRoute<T> extends PageRoute<T> {
  FadePageRoute({
    required this.builder,
    this.duration = const Duration(milliseconds: 300),
  });

  final WidgetBuilder builder;
  final Duration duration;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => true;

  @override
  Duration get transitionDuration => duration;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return FadeTransition(
      opacity: animation,
      child: builder(context),
    );
  }
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, _) {
        return MaterialApp(
          title: 'VisionVoice',
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: themeProvider.isDarkMode ? ThemeMode.dark : ThemeMode.light,
          home: const OCRHomePage(),
        );
      },
    );
  }
}

class LocalAIProcessor {
  static const int maxLength = 512; // TinyBERT's max sequence length
  late Interpreter _interpreter;
  bool _isInitialized = true;

  final Set<String> _stopWords = {
    'a', 'an', 'and', 'are', 'as', 'at', 'be', 'by', 'for', 'from', 
    'has', 'he', 'in', 'is', 'it', 'its', 'of', 'on', 'that', 'the', 
    'to', 'was', 'were', 'will', 'with'
  };


  Future<void> initialize() async {
    // Initialization code here
    return;
  }

  Future<String> generateSummary(String text) async {
    if (text.trim().isEmpty) {
      return "No text to summarize.";
    }

    // Preprocess text
    final preprocessedText = _preprocessText(text);
    final sentences = _splitIntoSentences(preprocessedText);
    
    if (sentences.isEmpty) {
      return "No valid sentences found to summarize.";
    }

    // Generate word frequency map
    final wordFrequencies = _calculateWordFrequencies(preprocessedText);
    
    // Score sentences using multiple criteria
    final scoredSentences = <Map<String, dynamic>>[];
    
    for (var i = 0; i < sentences.length; i++) {
      final sentence = sentences[i];
      final Map<String, double> scores = {
        'position': _calculatePositionScore(i, sentences.length),
        'length': _calculateLengthScore(sentence),
        'keyPhrase': _calculateKeyPhraseScore(sentence),
        'wordImportance': _calculateWordImportanceScore(sentence, wordFrequencies),
        'titleSimilarity': _calculateTitleSimilarityScore(sentence, sentences.first),
        'properNouns': _calculateProperNounScore(sentence),
        'numericData': _calculateNumericDataScore(sentence),
        'coherence': _calculateCoherenceScore(sentence, i > 0 ? sentences[i - 1] : null),
      };
      
      // Calculate weighted final score
      final double finalScore = _calculateWeightedScore(scores);
      
      scoredSentences.add({
        'sentence': sentence,
        'score': finalScore,
        'index': i,
      });
    }

    // Sort by score and select top sentences
    scoredSentences.sort((a, b) => (b['score'] as double).compareTo(a['score'] as double));
    
    // Determine optimal number of sentences based on text length
    final numSentences = _calculateOptimalSentenceCount(sentences.length);
    
    // Get top sentences and sort them by original position
    final topSentences = scoredSentences
        .take(numSentences)
        .toList()
      ..sort((a, b) => (a['index'] as int).compareTo(b['index'] as int));

    // Join sentences and post-process
    return _postProcessSummary(
      topSentences.map((s) => s['sentence'] as String).toList()
    );
  }

  String _preprocessText(String text) {
    return text
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'\n+'), ' ')
        .trim();
  }

  List<String> _splitIntoSentences(String text) {
    return text
        .split(RegExp(r'(?<=[.!?])\s+'))
        .where((s) => s.trim().length > 10) // Filter out very short sentences
        .toList();
  }

  Map<String, int> _calculateWordFrequencies(String text) {
    final words = text
        .toLowerCase()
        .split(RegExp(r'\W+'))
        .where((word) => word.isNotEmpty && !_stopWords.contains(word));
    
    return Map.fromIterable(
      words,
      key: (word) => word,
      value: (word) => words.where((w) => w == word).length
    );
  }

  double _calculatePositionScore(int position, int totalSentences) {
    if (position == 0) return 1.0; // First sentence
    if (position == totalSentences - 1) return 0.8; // Last sentence
    if (position < totalSentences * 0.2) return 0.7; // First 20% of text
    if (position > totalSentences * 0.8) return 0.6; // Last 20% of text
    return 0.5;
  }

  double _calculateLengthScore(String sentence) {
    final wordCount = sentence.split(' ').length;
    if (wordCount < 5) return 0.1;
    if (wordCount > 35) return 0.3;
    if (wordCount >= 10 && wordCount <= 25) return 1.0;
    return 0.5;
  }

  double _calculateKeyPhraseScore(String sentence) {
    final keyPhrases = {
      'important': 1.0,
      'significant': 1.0,
      'crucial': 1.0,
      'key finding': 1.0,
      'in conclusion': 1.0,
      'to summarize': 1.0,
      'therefore': 0.8,
      'consequently': 0.8,
      'as a result': 0.8,
      'research shows': 0.8,
      'study indicates': 0.8,
      'evidence suggests': 0.8,
    };

    double score = 0.0;
    final lowerSentence = sentence.toLowerCase();
    
    for (var entry in keyPhrases.entries) {
      if (lowerSentence.contains(entry.key)) {
        score += entry.value;
      }
    }
    
    return score.clamp(0.0, 1.0);
  }

  double _calculateWordImportanceScore(String sentence, Map<String, int> wordFrequencies) {
    final words = sentence
        .toLowerCase()
        .split(RegExp(r'\W+'))
        .where((word) => word.isNotEmpty && !_stopWords.contains(word));
    
    if (words.isEmpty) return 0.0;
    
    final totalScore = words.fold<double>(
      0.0,
      (score, word) => score + (wordFrequencies[word] ?? 0)
    );
    
    return (totalScore / words.length).clamp(0.0, 1.0);
  }

  double _calculateTitleSimilarityScore(String sentence, String title) {
    final titleWords = title
        .toLowerCase()
        .split(RegExp(r'\W+'))
        .where((word) => word.isNotEmpty && !_stopWords.contains(word))
        .toSet();
    
    final sentenceWords = sentence
        .toLowerCase()
        .split(RegExp(r'\W+'))
        .where((word) => word.isNotEmpty && !_stopWords.contains(word))
        .toSet();
    
    if (titleWords.isEmpty) return 0.0;
    
    final commonWords = titleWords.intersection(sentenceWords);
    return (commonWords.length / titleWords.length).clamp(0.0, 1.0);
  }

  double _calculateProperNounScore(String sentence) {
    final properNouns = RegExp(r'\b[A-Z][a-z]+\b');
    final matches = properNouns.allMatches(sentence);
    return (matches.length * 0.2).clamp(0.0, 1.0);
  }

  double _calculateNumericDataScore(String sentence) {
    final numbers = RegExp(r'\b\d+(?:\.\d+)?%?\b');
    final matches = numbers.allMatches(sentence);
    return (matches.length * 0.3).clamp(0.0, 1.0);
  }

  double _calculateCoherenceScore(String sentence, String? previousSentence) {
    if (previousSentence == null) return 1.0;
    
    final pronouns = RegExp(r'\b(it|they|this|these|those|he|she)\b', caseSensitive: false);
    if (pronouns.hasMatch(sentence)) {
      return 0.5; // Reduce score for sentences that might lack context
    }
    
    return 1.0;
  }

  double _calculateWeightedScore(Map<String, double> scores) {
    final weights = {
      'position': 0.15,
      'length': 0.10,
      'keyPhrase': 0.15,
      'wordImportance': 0.20,
      'titleSimilarity': 0.15,
      'properNouns': 0.10,
      'numericData': 0.10,
      'coherence': 0.05,
    };

    double weightedScore = 0.0;
    weights.forEach((key, weight) {
      weightedScore += (scores[key] ?? 0.0) * weight;
    });
    
    return weightedScore;
  }

  int _calculateOptimalSentenceCount(int totalSentences) {
    if (totalSentences <= 3) return totalSentences;
    if (totalSentences <= 6) return 3;
    if (totalSentences <= 10) return 4;
    return (totalSentences * 0.3).round().clamp(4, 7);
  }

  String _postProcessSummary(List<String> sentences) {
    return sentences
        .map((s) => s.trim())
        .join(' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  void dispose() {
    // Add cleanup code here if needed
  }
}

class ThemeProvider with ChangeNotifier {
  bool _isDarkMode = false;
  bool get isDarkMode => _isDarkMode;

  ThemeProvider() {
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    _isDarkMode = prefs.getBool('isDarkMode') ?? 
      WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark;
    notifyListeners();
  }

  Future<void> toggleTheme() async {
    _isDarkMode = !_isDarkMode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isDarkMode', _isDarkMode);
    notifyListeners();
  }
}

// Add this service to handle global navigation
class NavigationService {
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
}

// Custom theme data
class AppTheme {
  static ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: ColorScheme.fromSeed(
      seedColor: Colors.blue,
      brightness: Brightness.light,
    ),
    textTheme: GoogleFonts.interTextTheme(),
    cardTheme: CardTheme(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
    ),
    appBarTheme: AppBarTheme(
      elevation: 0,
      centerTitle: true,
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      titleTextStyle: GoogleFonts.inter(
        color: Colors.black,
        fontSize: 20,
        fontWeight: FontWeight.w600,
      ),
    ),
    tabBarTheme: TabBarTheme(
      labelStyle: GoogleFonts.inter(fontWeight: FontWeight.w600),
      unselectedLabelStyle: GoogleFonts.inter(),
      indicatorSize: TabBarIndicatorSize.label,
    ),
  );

  static ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(
      seedColor: Colors.blue,
      brightness: Brightness.dark,
    ),
    textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
    cardTheme: CardTheme(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade800),
      ),
    ),
    appBarTheme: AppBarTheme(
      elevation: 0,
      centerTitle: true,
      backgroundColor: Colors.grey.shade900,
      surfaceTintColor: Colors.grey.shade900,
      titleTextStyle: GoogleFonts.inter(
        color: Colors.white,
        fontSize: 20,
        fontWeight: FontWeight.w600,
      ),
    ),
    tabBarTheme: TabBarTheme(
      labelStyle: GoogleFonts.inter(fontWeight: FontWeight.w600),
      unselectedLabelStyle: GoogleFonts.inter(),
      indicatorSize: TabBarIndicatorSize.label,
    ),
  );
}

// Custom animated theme toggle widget
class AnimatedThemeToggle extends StatelessWidget {
  final bool isDarkMode;
  final VoidCallback onToggle;

  const AnimatedThemeToggle({
    Key? key,
    required this.isDarkMode,
    required this.onToggle,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onToggle,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutBack,
        width: 60,
        height: 32,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: isDarkMode ? Colors.grey.shade800 : Colors.blue.shade100,
        ),
        child: Stack(
          children: [
            AnimatedPositioned(
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOutBack,
              left: isDarkMode ? 28 : 0,
              top: 0,
              child: Container(
                padding: const EdgeInsets.all(4),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: isDarkMode ? _buildMoon() : _buildSun(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSun() {
    return Container(
      key: const ValueKey('sun'),
      width: 24,
      height: 24,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.amber,
      ),
      child: Center(
        child: CustomPaint(
          painter: SunRaysPainter(),
          size: const Size(24, 24),
        ),
      ),
    );
  }

  Widget _buildMoon() {
    return Container(
      key: const ValueKey('moon'),
      width: 24,
      height: 24,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
      ),
      child: Stack(
        children: [
          Positioned(
            top: 2,
            left: 2,
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.grey.shade800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class SunRaysPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.amber.shade200
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    final center = Offset(size.width / 2, size.height / 2);
    const rayLength = 4.0;

    for (var i = 0; i < 8; i++) {
      final angle = i * 45 * pi / 180;
      final start = Offset(
        center.dx + cos(angle) * (size.width / 2 + 2),
        center.dy + sin(angle) * (size.height / 2 + 2),
      );
      final end = Offset(
        center.dx + cos(angle) * (size.width / 2 + rayLength + 2),
        center.dy + sin(angle) * (size.height / 2 + rayLength + 2),
      );
      canvas.drawLine(start, end, paint);
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}

class OCRHomePage extends StatefulWidget {
  const OCRHomePage({Key? key}) : super(key: key);

  @override
  State<OCRHomePage> createState() => _OCRHomePageState();
}

class _OCRHomePageState extends State<OCRHomePage> with SingleTickerProviderStateMixin {
  final LocalAIProcessor _aiProcessor = LocalAIProcessor();
  String _summary = '';
  bool _isProcessingAI = false;
  final GoogleTranslator _translator = GoogleTranslator();
  late TabController _tabController;
  String _translatedText = '';
  final ImagePicker _picker = ImagePicker();
  final FlutterTts _flutterTts = FlutterTts();
  final List<Map<String, String>> _languageData = [
    {'code': 'en', 'name': 'English', 'ttsCode': 'en-US'},
    {'code': 'es', 'name': 'Español', 'ttsCode': 'es-ES'},
    {'code': 'fr', 'name': 'Français', 'ttsCode': 'fr-FR'},
    {'code': 'de', 'name': 'Deutsch', 'ttsCode': 'de-DE'},
    {'code': 'hi', 'name': 'हिंदी', 'ttsCode': 'hi-IN'},
    {'code': 'zh', 'name': '中文', 'ttsCode': 'zh-CN'},
  ];
  String _currentLanguage = 'en';
  XFile? _image;
  String _recognizedText = '';
  bool _isProcessing = false;
  bool _autoRead = true;
  double _textSize = 18.0;

  @override
  void initState() {
    super.initState();
    _initializeSettings();
    _initializeTTS();
    _configureAccessibility();
    _initializeAI();
    _tabController = TabController(length: 3, vsync: this);
  }

  Future<void> _initializeAI() async {
    await _aiProcessor.initialize();
  }

  Future<void> _generateSummary() async {
    if (_recognizedText.isEmpty) return;

    setState(() => _isProcessingAI = true);
    
    try {
      final summary = await _aiProcessor.generateSummary(_recognizedText);
      setState(() {
        _summary = summary;
        _isProcessingAI = false;
      });
    } catch (e) {
      _showAccessibleError('Error generating summary: ${e.toString()}');
      setState(() => _isProcessingAI = false);
    }
  }

  Future<void> _translateText() async {
    if (_recognizedText.isEmpty) return;
    
    try {
      final translation = await _translator.translate(
        _recognizedText,
        from: 'auto',
        to: _currentLanguage,
      );
      
      setState(() {
        _translatedText = translation.text;
      });
      
      if (_autoRead) {
        await _speakText(_translatedText);
      }
    } catch (e) {
      _showAccessibleError('Translation error: ${e.toString()}');
    }
  }

  Future<void> _initializeSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _currentLanguage = prefs.getString('language') ?? 'en';
      _autoRead = prefs.getBool('autoRead') ?? true;
      _textSize = prefs.getDouble('textSize') ?? 18.0;
    });
  }

  Future<void> _initializeTTS() async {
    try {
      final languageData = _languageData.firstWhere((lang) => lang['code'] == _currentLanguage);
      await _flutterTts.setLanguage(languageData['ttsCode']!);
      await _flutterTts.setSpeechRate(0.5); // Slower speech rate
      await _flutterTts.setVolume(1.0); // Maximum volume
      await _flutterTts.setPitch(1.0); // Default pitch

      // Check if language is available
      final available = await _flutterTts.isLanguageAvailable(languageData['ttsCode']!);
      if (!available) {
        _showAccessibleError('Selected language is not available on this device');
      }
    } catch (e) {
      _showAccessibleError('Error initializing text-to-speech: $e');
    }
  }

  void _configureAccessibility() {
    // Configure system-wide accessibility settings
    SystemChannels.textInput.invokeMethod('TextInput.setAccessibilityFeatures', {
      'highContrast': true,
      'largeText': true,
    });
  }

  Future<void> _pickImage() async {
    try {
      // Provide audio feedback before camera opens
      await _flutterTts.speak("Opening camera. Please hold steady.");
      await Vibration.vibrate(duration: 100);

      final XFile? pickedFile = await _picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.rear,
        maxWidth: 1800,
        maxHeight: 1800,
        imageQuality: 96,
      );

      if (pickedFile != null) {
        setState(() {
          _image = pickedFile;
          _recognizedText = '';
          _isProcessing = true;
        });

        await _processImage(File(pickedFile.path));
      }
    } catch (e) {
      _showAccessibleError('Error capturing image: ${e.toString()}');
    }
  }

  Future<void> _processImage(File image) async {
    try {
      final inputImage = InputImage.fromFile(image);
      final textRecognizer = GoogleMlKit.vision.textRecognizer();

      final RecognizedText recognizedText = await textRecognizer.processImage(inputImage);

      setState(() {
        _recognizedText = recognizedText.text;
        _isProcessing = false;
      });

      if (_recognizedText.isNotEmpty) {
        await _translateText();
        if (_autoRead) {
          await _speakText(_currentLanguage == 'en' ? _recognizedText : _translatedText);
        }
      } else {
        await _speakText("No text found in the image. Please try again.");
      }

      await textRecognizer.close();
    } catch (e) {
      setState(() => _isProcessing = false);
      _showAccessibleError('Error processing image: ${e.toString()}');
    }
  }

  Future<void> _speakText(String text) async {
    await _flutterTts.stop();
    await _flutterTts.speak(text);
  }

  void _showAccessibleError(String message) {
    _flutterTts.speak("Error: $message");
    Vibration.vibrate(duration: 500);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: TextStyle(
            color: Colors.white,
            fontSize: _textSize,
          ),
        ),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 5),
      ),
    );
  }

  Future<void> _changeLanguage(String languageCode) async {
    try {
      final languageData = _languageData.firstWhere((lang) => lang['code'] == languageCode);

      // Update TTS language
      final ttsResult = await _flutterTts.setLanguage(languageData['ttsCode']!);

      if (ttsResult == 1) {  // TTS language set successfully
        setState(() => _currentLanguage = languageCode);

        // Save to preferences
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('language', languageCode);

        // Confirm change with audio feedback
        await _flutterTts.speak("Language changed to ${languageData['name']}");

        // Optional: Vibrate for feedback
        await Vibration.vibrate(duration: 100);
      } else {
        _showAccessibleError('Language ${languageData['name']} is not supported on this device');
      }
    } catch (e) {
      _showAccessibleError('Error changing language: $e');
    }
  }

  @override
Widget build(BuildContext context) {
  return Consumer<ThemeProvider>(
    builder: (context, themeProvider, _) => Scaffold(
      appBar: AppBar(
        title: Text(
          'VisionVoice',
          style: TextStyle(fontSize: _textSize + 4),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _showSettings,
            tooltip: 'Settings',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(
              child: Text(
                'Original',
                style: TextStyle(fontSize: _textSize),
              ),
            ),
            Tab(
              child: Text(
                'Translated',
                style: TextStyle(fontSize: _textSize),
              ),
            ),
            Tab(
              child: Text(
                'Summary',
                style: TextStyle(fontSize: _textSize),
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: TabBarView(
          controller: _tabController,
          children: [
            // Original Text Tab
            SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    if (_image != null)
                      Container(
                        constraints: const BoxConstraints(maxHeight: 300),
                        child: Image.file(File(_image!.path)),
                      ),
                    if (_isProcessing)
                      Column(
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: 8),
                          Text(
                            'Processing image...',
                            style: TextStyle(fontSize: _textSize),
                          ),
                        ],
                      ),
                    if (_recognizedText.isNotEmpty)
                      _buildTextCard(_recognizedText, true),
                  ],
                ),
              ),
            ),
            // Translated Text Tab
            SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    if (_translatedText.isNotEmpty)
                      _buildTextCard(_translatedText, false),
                  ],
                ),
              ),
            ),
            // Summary Tab
            _buildAITab(),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.large(
        onPressed: _pickImage,
        tooltip: 'Capture Image',
        child: const Icon(Icons.camera_alt, size: 36),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    ),
  );
}


  Widget _buildAITab() {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_isProcessingAI) ...[
              const Center(child: CircularProgressIndicator()),
              const SizedBox(height: 16),
              Center(
                child: Text(
                  'Generating summary...',
                  style: TextStyle(fontSize: _textSize),
                ),
              ),
            ] else if (_recognizedText.isNotEmpty && _summary.isEmpty) ...[
              Center(
                child: ElevatedButton.icon(
                  onPressed: _generateSummary,
                  icon: const Icon(Icons.auto_awesome),
                  label: Text(
                    'Generate Summary',
                    style: TextStyle(fontSize: _textSize),
                  ),
                ),
              ),
            ],
            if (_summary.isNotEmpty) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.summarize),
                          const SizedBox(width: 8),
                          Text(
                            'Summary',
                            style: TextStyle(
                              fontSize: _textSize + 2,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _summary,
                        style: TextStyle(fontSize: _textSize),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.volume_up),
                            onPressed: () => _speakText(_summary),
                            tooltip: 'Read summary',
                          ),
                          IconButton(
                            icon: const Icon(Icons.copy),
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: _summary));
                              _flutterTts.speak("Summary copied to clipboard");
                            },
                            tooltip: 'Copy summary',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTextCard(String text, bool isOriginal) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text(
              text,
              style: TextStyle(fontSize: _textSize),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  icon: const Icon(Icons.volume_up),
                  onPressed: () => _speakText(text),
                  tooltip: 'Read aloud',
                ),
                IconButton(
                  icon: const Icon(Icons.copy),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: text));
                    _flutterTts.speak("Text copied to clipboard");
                  },
                  tooltip: 'Copy text',
                ),
                if (isOriginal) // Only show summarize button for original text
                IconButton(
                  icon: const Icon(Icons.auto_awesome),
                  onPressed: () {
                    _tabController.animateTo(2); // Switch to summary tab
                    _generateSummary();
                  },
                  tooltip: 'Generate summary',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Update your settings dialog
void _showSettings() {
  showDialog(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        backgroundColor: Theme.of(context).dialogBackgroundColor,
        title: Text(
          'Settings',
          style: TextStyle(
            fontSize: _textSize,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Consumer<ThemeProvider>(
          builder: (context, themeProvider, child) {
            bool isDarkMode = themeProvider.isDarkMode; // Retrieve current theme mode
            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Theme Toggle
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Theme',
                          style: TextStyle(fontSize: _textSize),
                        ),
                        AnimatedThemeToggle(
                          isDarkMode: isDarkMode,
                          onToggle: () {
                            themeProvider.toggleTheme();
                            setDialogState(() {}); // Refresh dialog state
                          },
                        ),
                      ],
                    ),
                  ),

                  const Divider(),

                  // Language Selection
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Language',
                          style: TextStyle(
                            fontSize: _textSize,
                            color: isDarkMode ? Colors.white : Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            color: isDarkMode ? Colors.grey[800] : Colors.grey[100],
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _currentLanguage,
                              isExpanded: true,
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              borderRadius: BorderRadius.circular(12),
                              dropdownColor: isDarkMode ? Colors.grey[800] : Colors.grey[100],
                              items: _languageData.map((Map<String, String> lang) {
                                return DropdownMenuItem(
                                  value: lang['code'],
                                  child: Text(
                                    '${lang['name']} (${lang['code']?.toUpperCase()})',
                                    style: TextStyle(
                                      fontSize: _textSize,
                                      color: isDarkMode ? Colors.white : Colors.black87,
                                    ),
                                  ),
                                );
                              }).toList(),
                              onChanged: (String? newValue) {
                                if (newValue != null) {
                                  Navigator.pop(context);
                                  _changeLanguage(newValue);
                                }
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const Divider(),

                  // Auto-read Toggle
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: SwitchListTile(
                      title: Text(
                        'Auto-read text',
                        style: TextStyle(
                          fontSize: _textSize,
                          color: isDarkMode ? Colors.white : Colors.black87,
                        ),
                      ),
                      value: _autoRead,
                      activeColor: Colors.blue,
                      onChanged: (bool value) async {
                        setDialogState(() {
                          _autoRead = value;
                        });
                        setState(() {
                          _autoRead = value;
                        });
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setBool('autoRead', value);
                      },
                    ),
                  ),

                  const Divider(),

                  // Text Size Controls
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Text Size: ${_textSize.toStringAsFixed(1)}',
                          style: TextStyle(
                            fontSize: _textSize,
                            color: isDarkMode ? Colors.white : Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Text(
                              'A',
                              style: TextStyle(
                                fontSize: 14,
                                color: isDarkMode ? Colors.white : Colors.black87,
                              ),
                            ),
                            Expanded(
                              child: SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  activeTrackColor: Colors.blue,
                                  inactiveTrackColor: isDarkMode ? Colors.grey[700] : Colors.grey[300],
                                  thumbColor: Colors.blue,
                                  overlayColor: Colors.blue.withOpacity(0.3),
                                ),
                                child: Slider(
                                  value: _textSize,
                                  min: 14.0,
                                  max: 30.0,
                                  divisions: 32,
                                  onChanged: (double value) async {
                                    setDialogState(() {
                                      _textSize = value;
                                    });
                                    setState(() {
                                      _textSize = value;
                                    });
                                    final prefs = await SharedPreferences.getInstance();
                                    await prefs.setDouble('textSize', value);
                                  },
                                ),
                              ),
                            ),
                            Text(
                              'A',
                              style: TextStyle(
                                fontSize: 30,
                                color: isDarkMode ? Colors.white : Colors.black87,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const Divider(),

                  // Preview Text
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Preview',
                          style: TextStyle(
                            fontSize: _textSize,
                            fontWeight: FontWeight.bold,
                            color: isDarkMode ? Colors.white : Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            color: isDarkMode ? Colors.grey[800] : Colors.grey[100],
                          ),
                          child: Text(
                            'This is how your text will look.',
                            style: TextStyle(
                              fontSize: _textSize,
                              color: isDarkMode ? Colors.white : Colors.black87,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              'Close',
              style: TextStyle(
                fontSize: _textSize,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

  @override
  void dispose() {
    _flutterTts.stop();
    _tabController.dispose();
    _aiProcessor.dispose();
    super.dispose();
  }
}