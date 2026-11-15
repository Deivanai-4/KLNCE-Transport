import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../main.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';
import '../config/app_config.dart';
import 'student/home_screen.dart';
import 'admin/admin_home.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _obscurePass = true;
  bool _isCheckingConnection = false;
  bool? _isServerConnected;

  @override
  void initState() {
    super.initState();
    _checkServerAvailability();
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  /// Silently checks backend availability on screen load
  Future<void> _checkServerAvailability() async {
    final ok = await ApiService.testHealth();
    if (mounted) {
      setState(() {
        _isServerConnected = ok;
      });
    }
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    final auth = context.read<AuthService>();
    final ok = await auth.login(_emailCtrl.text.trim(), _passCtrl.text);
    if (!mounted || !ok) return;

    final destination =
        auth.isAdmin ? const AdminHomeScreen() : const StudentHomeScreen();
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => destination),
    );
  }

  void _browseSchedules() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const StudentHomeScreen()),
    );
  }

  /// Clean dialog to test connection to the Production Server
  void _showTestConnectionDialog() {
    final urlCtrl = TextEditingController(text: AppConfig.apiBaseUrl);
    bool isTesting = false;
    bool? testOk = _isServerConnected;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.md),
          ),
          title: Row(
            children: [
              Icon(
                testOk == true ? Icons.cloud_done : Icons.cloud_outlined,
                color:
                    testOk == true ? const Color(0xFF2E7D32) : AppColors.navy,
                size: 24,
              ),
              const SizedBox(width: AppSpacing.sm),
              const Text(
                'Server Status',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Production Server URL',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: urlCtrl,
                  decoration: InputDecoration(
                    hintText: 'https://your-server.com/api',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.restore, size: 18),
                      tooltip: 'Reset to default',
                      onPressed: () {
                        setDialogState(() {
                          urlCtrl.text = AppConfig.productionApiUrl;
                        });
                      },
                    ),
                  ),
                  style: const TextStyle(fontSize: 13),
                ),
                const SizedBox(height: AppSpacing.md),
                Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: AppSpacing.sm,
                    horizontal: AppSpacing.md,
                  ),
                  decoration: BoxDecoration(
                    color: testOk == null
                        ? AppColors.surface
                        : (testOk!
                            ? const Color(0xFFE8F5E9)
                            : const Color(0xFFFFEBEE)),
                    borderRadius: BorderRadius.circular(AppRadii.sm),
                    border: Border.all(
                      color: testOk == null
                          ? Colors.black12
                          : (testOk!
                              ? const Color(0xFFA5D6A7)
                              : const Color(0xFFFFCDD2)),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        testOk == null
                            ? Icons.help_outline
                            : (testOk!
                                ? Icons.check_circle
                                : Icons.cancel_outlined),
                        size: 20,
                        color: testOk == null
                            ? AppColors.textSecondary
                            : (testOk!
                                ? const Color(0xFF2E7D32)
                                : const Color(0xFFC62828)),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          testOk == null
                              ? 'Tap Test Connection to verify'
                              : (testOk!
                                  ? 'Connected: Production server is online'
                                  : 'Connection Failed: Server is unreachable'),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: testOk == null
                                ? AppColors.textSecondary
                                : (testOk!
                                    ? const Color(0xFF2E7D32)
                                    : const Color(0xFFC62828)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
            OutlinedButton.icon(
              onPressed: isTesting
                  ? null
                  : () async {
                      setDialogState(() {
                        isTesting = true;
                      });
                      final ok =
                          await ApiService.testHealth(urlCtrl.text.trim());
                      setDialogState(() {
                        isTesting = false;
                        testOk = ok;
                      });
                      if (mounted) {
                        setState(() {
                          _isServerConnected = ok;
                        });
                      }
                    },
              icon: isTesting
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.refresh, size: 16),
              label: Text(isTesting ? 'Testing...' : 'Test Connection'),
            ),
            ElevatedButton(
              onPressed: () async {
                final newUrl = urlCtrl.text.trim();
                if (newUrl.isNotEmpty) {
                  await AppConfig.setCustomApiUrl(newUrl);
                } else {
                  await AppConfig.setCustomApiUrl(null);
                }
                final ok = await ApiService.testHealth();
                if (mounted) {
                  setState(() {
                    _isServerConnected = ok;
                  });
                }
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      KlnceBrandLockup(onTap: _browseSchedules),
                      // Clean Test Connection Button (replaces complicated dev settings)
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          backgroundColor: _isServerConnected == true
                              ? const Color(0xFFE8F5E9)
                              : (_isServerConnected == false
                                  ? const Color(0xFFFFEBEE)
                                  : Colors.black.withValues(alpha: 0.04)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                        onPressed: _showTestConnectionDialog,
                        icon: _isCheckingConnection
                            ? const SizedBox(
                                width: 12,
                                height: 12,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Icon(
                                Icons.circle,
                                size: 10,
                                color: _isServerConnected == true
                                    ? const Color(0xFF2E7D32)
                                    : (_isServerConnected == false
                                        ? const Color(0xFFC62828)
                                        : AppColors.textSecondary),
                              ),
                        label: Text(
                          _isServerConnected == true
                              ? 'Connected'
                              : (_isServerConnected == false
                                  ? 'Connection Failed'
                                  : 'Test Connection'),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _isServerConnected == true
                                ? const Color(0xFF2E7D32)
                                : (_isServerConnected == false
                                    ? const Color(0xFFC62828)
                                    : AppColors.textPrimary),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  Text(
                    'Welcome back',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Sign in to your college transport account. You can browse published schedules without signing in.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                  ),
                  const SizedBox(height: 24),
                  Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextFormField(
                          controller: _emailCtrl,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.username],
                          decoration: const InputDecoration(
                            labelText: 'College email',
                            hintText: 'name@college.edu',
                            prefixIcon: Icon(Icons.email_outlined),
                          ),
                          validator: (value) {
                            final email = value?.trim() ?? '';
                            if (email.isEmpty) return 'Enter your email';
                            if (!email.contains('@')) {
                              return 'Enter a valid email address';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: AppSpacing.md),
                        TextFormField(
                          controller: _passCtrl,
                          obscureText: _obscurePass,
                          textInputAction: TextInputAction.done,
                          autofillHints: const [AutofillHints.password],
                          onFieldSubmitted: (_) => _login(),
                          decoration: InputDecoration(
                            labelText: 'Password',
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              tooltip: _obscurePass
                                  ? 'Show password'
                                  : 'Hide password',
                              onPressed: () => setState(
                                () => _obscurePass = !_obscurePass,
                              ),
                              icon: Icon(
                                _obscurePass
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                            ),
                          ),
                          validator: (value) => value == null || value.isEmpty
                              ? 'Enter your password'
                              : null,
                        ),
                        if (auth.errorMessage != null) ...[
                          const SizedBox(height: AppSpacing.md),
                          Container(
                            padding: const EdgeInsets.all(AppSpacing.sm),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFEBEE),
                              borderRadius: BorderRadius.circular(AppRadii.sm),
                              border:
                                  Border.all(color: const Color(0xFFFFCDD2)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.error_outline,
                                    color: Color(0xFFC62828), size: 18),
                                const SizedBox(width: AppSpacing.xs),
                                Expanded(
                                  child: Text(
                                    auth.errorMessage!,
                                    style: const TextStyle(
                                      color: Color(0xFFC62828),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: AppSpacing.lg),
                        SizedBox(
                          height: 50,
                          child: ElevatedButton(
                            onPressed: auth.isLoading ? null : _login,
                            child: auth.isLoading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text('Sign in'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextButton(
                    onPressed: _browseSchedules,
                    child: const Text('Browse schedules without signing in'),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    'Account access is managed by the college transport office.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
