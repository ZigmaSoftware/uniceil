import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:wpe_summit_attendance_2026/UI/api.dart';
import 'package:wpe_summit_attendance_2026/UI/selfie_camera_page.dart';
import 'package:wpe_summit_attendance_2026/location_access.dart';

const _navy = Color(0xFF174D3A);
const _navyLight = Color(0xFF2C6A50);
const _inGreen = Color(0xFF0E7A44);
const _outGreen = Color(0xFF2A6249);
const _bg = Color(0xFFF4FBF6);
const _surface = Colors.white;
const _textPrimary = Color(0xFF173B2D);
const _errorRed = Color(0xFFD32F2F);
const _cardInk = Color(0xFF171717);
const _cardLabel = Color(0xFF67716C);

class PunchAttendanceScreen extends StatefulWidget {
  const PunchAttendanceScreen({super.key});

  @override
  State<PunchAttendanceScreen> createState() => _PunchAttendanceScreenState();
}

class _PunchAttendanceScreenState extends State<PunchAttendanceScreen> {
  final _idController = TextEditingController();
  final _idFocus = FocusNode();
  final _apiService = ApiService();

  Map<String, dynamic>? _employee;
  Map<String, dynamic>? _todayStatus;
  bool _isLookingUp = false;
  bool _isSubmitting = false;
  String? _errorMessage;

  String get _nextAction =>
      (_todayStatus?['next_action']?.toString() ?? 'IN').toUpperCase();

  bool get _isIn => _nextAction == 'IN';

  Color get _actionColor => _isIn ? _inGreen : _outGreen;

  @override
  void initState() {
    super.initState();
    _focusIdField();
  }

  @override
  void dispose() {
    _idController.dispose();
    _idFocus.dispose();
    super.dispose();
  }

  void _focusIdField() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _idFocus.requestFocus();
    });
  }

  void _dismissKeyboard() {
    _idFocus.unfocus();
    FocusManager.instance.primaryFocus?.unfocus();
  }

  void _resetDesk() {
    setState(() {
      _employee = null;
      _todayStatus = null;
      _errorMessage = null;
      _idController.clear();
    });
    _focusIdField();
  }

  Future<void> _lookup() async {
    _dismissKeyboard();
    final normalizedId = _apiService.normalizeEmployeeId(_idController.text);
    if (normalizedId.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter a valid attendee ID.';
        _employee = null;
        _todayStatus = null;
      });
      _focusIdField();
      return;
    }

    setState(() {
      _isLookingUp = true;
      _errorMessage = null;
      _employee = null;
      _todayStatus = null;
    });

    try {
      final response = await _apiService.lookupAttendee(normalizedId);
      if (!mounted) return;
      setState(() {
        _employee = Map<String, dynamic>.from(response['employee'] as Map);
        _todayStatus = Map<String, dynamic>.from(response['today'] as Map);
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _employee = null;
        _todayStatus = null;
        _errorMessage = e.message;
      });
      _focusIdField();
    } finally {
      if (mounted) {
        setState(() => _isLookingUp = false);
      }
    }
  }

  Future<void> _captureAndSubmit() async {
    if (_employee == null || _isSubmitting) return;

    _dismissKeyboard();
    final actionLabel = _nextAction;
    final image = await showGeneralDialog<XFile>(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'Capture photo',
      barrierColor: Colors.black.withValues(alpha: 0.72),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (context, animation, secondaryAnimation) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 12, 10, 18),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(30),
              child: Material(
                color: Colors.black,
                child: SelfieCameraPage(actionLabel: actionLabel),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.97, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    );

    if (!mounted || image == null) return;
    await _submitCapturedPunch(image);
  }

  Future<void> _submitCapturedPunch(XFile image) async {
    final employee = _employee;
    if (employee == null) return;

    setState(() => _isSubmitting = true);

    try {
      final position = await LocationAccess.currentPunchPosition();
      final response = await _apiService.submitPunch(
        employeeId: employee['employee_id'].toString(),
        captureImage: image,
        latitude: position.latitude,
        longitude: position.longitude,
      );
      if (!mounted) return;

      final attendance = Map<String, dynamic>.from(
        response['attendance'] as Map,
      );
      final submittedEmployee = Map<String, dynamic>.from(
        response['employee'] as Map,
      );
      final action = response['action'].toString().toUpperCase();
      final punchTime =
          (action == 'IN'
                  ? attendance['punch_in_label']
                  : attendance['punch_out_label'])
              ?.toString();

      _resetDesk();
      _showSuccessToast(
        name: (submittedEmployee['employee_name'] ?? 'Attendee').toString(),
        punchTime: punchTime,
      );
    } on LocationAccessException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(e.message),
            backgroundColor: _errorRed,
            behavior: SnackBarBehavior.floating,
          ),
        );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(e.message),
            backgroundColor: _errorRed,
            behavior: SnackBarBehavior.floating,
          ),
        );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  void _showSuccessToast({
    required String name,
    String? punchTime,
  }) {
    const color = _navy;
    final subtitle = punchTime == null || punchTime.isEmpty
        ? name
        : '$name  •  $punchTime';

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: color,
          duration: const Duration(seconds: 2),
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Attendance captured',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.88),
                        fontSize: 12,
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

  @override
  Widget build(BuildContext context) {
    final pageTheme = Theme.of(context).copyWith(
      colorScheme: ColorScheme.fromSeed(
        seedColor: _inGreen,
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: _bg,
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: _navy),
    );

    return Theme(
      data: pageTheme,
      child: Scaffold(
        backgroundColor: _bg,
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _dismissKeyboard,
          child: CustomScrollView(
            slivers: [
              _buildAppBar(),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    children: [
                      _buildIdCard(),
                      if (_errorMessage != null) ...[
                        const SizedBox(height: 10),
                        _ErrorBanner(message: _errorMessage!),
                      ],
                    ],
                  ),
                ),
              ),
              if (_employee != null)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                  sliver: SliverFillRemaining(
                    hasScrollBody: false,
                    child: _buildEmployeeCard(),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return SliverAppBar(
      pinned: true,
      toolbarHeight: 64,
      backgroundColor: _navy,
      foregroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      flexibleSpace: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [_navy, _navyLight],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
      ),
      titleSpacing: 16,
      title: const Text(
        'Punch Attendance',
        style: TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  Widget _buildIdCard() {
    return _Card(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              _IconBubble(icon: Icons.badge_rounded, color: _navy),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Find attendee',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: _textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5FBF7),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: const Color(0xFFD4E7DB),
                      width: 1.2,
                    ),
                  ),
                  child: TextField(
                    controller: _idController,
                    focusNode: _idFocus,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.search,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onSubmitted: (_) => _lookup(),
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: _textPrimary,
                      letterSpacing: 4,
                    ),
                    textAlign: TextAlign.center,
                    decoration: const InputDecoration(
                      hintText: '001',
                      hintStyle: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w300,
                        color: Color(0xFFB2C8BA),
                        letterSpacing: 4,
                      ),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _LookupButton(isLoading: _isLookingUp, onTap: _lookup),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmployeeCard() {
    final employee = _employee!;
    final name = (employee['employee_name'] ?? '').toString();
    final employeeId = (employee['employee_id'] ?? '').toString().trim();
    final designation = (employee['designation'] ?? '').toString().trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Card(
          borderColor: const Color(0xFFE3EBE6),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Attendee Details',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: _cardInk,
                  letterSpacing: 0.1,
                ),
              ),
              const SizedBox(height: 14),
              const Divider(height: 1, color: Color(0xFFE8EEEA)),
              const SizedBox(height: 14),
              _EmployeeDetailLine(label: 'Name', value: name),
              const SizedBox(height: 10),
              _EmployeeDetailLine(
                label: 'Designation',
                value: designation.isEmpty ? 'Attendee' : designation,
                valueColor: _inGreen,
              ),
              const SizedBox(height: 10),
              _EmployeeDetailLine(
                label: 'Attendee ID',
                value: employeeId,
              ),
              const SizedBox(height: 10),
              const Text(
                'Verify the attendee details before capturing attendance.',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  color: _cardLabel,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Center(
            child: _CaptureLauncher(
              color: _actionColor,
              isBusy: _isSubmitting,
              onTap: _captureAndSubmit,
            ),
          ),
        ),
        if (_isSubmitting) ...[
          const SizedBox(height: 12),
          Text(
            'Capturing location and saving punch...',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: _actionColor,
            ),
          ),
        ],
      ],
    );
  }
}

class _EmployeeDetailLine extends StatelessWidget {
  const _EmployeeDetailLine({
    required this.label,
    required this.value,
    this.valueColor = _cardInk,
  });

  final String label;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$label: ',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: _cardLabel,
            ),
          ),
          TextSpan(
            text: value,
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              color: valueColor,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    required this.child,
    this.borderColor,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final Color? borderColor;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: borderColor ?? const Color(0xFFE1ECE5),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _IconBubble extends StatelessWidget {
  const _IconBubble({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: color, size: 20),
    );
  }
}

class _LookupButton extends StatelessWidget {
  const _LookupButton({required this.isLoading, required this.onTap});

  final bool isLoading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isLoading ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 52,
        height: 54,
        decoration: BoxDecoration(
          color: isLoading ? _navy.withValues(alpha: 0.55) : _navy,
          borderRadius: BorderRadius.circular(14),
        ),
        child: isLoading
            ? const Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2.4,
                  ),
                ),
              )
            : const Icon(Icons.search_rounded, color: Colors.white, size: 24),
      ),
    );
  }
}

class _CaptureLauncher extends StatelessWidget {
  const _CaptureLauncher({
    required this.color,
    required this.isBusy,
    required this.onTap,
  });

  final Color color;
  final bool isBusy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: InkWell(
        onTap: isBusy ? null : onTap,
        borderRadius: BorderRadius.circular(999),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(
                  color: color.withValues(alpha: 0.2),
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.25),
                    blurRadius: 30,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: isBusy
                  ? const Center(
                      child: SizedBox(
                        width: 46,
                        height: 46,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.8,
                          color: _inGreen,
                        ),
                      ),
                    )
                  : Icon(Icons.camera_alt_rounded, color: color, size: 108),
            ),
            const SizedBox(height: 16),
            Text(
              'Capture Attendance',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFEBEE),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _errorRed.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: _errorRed, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 13,
                color: _errorRed,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
