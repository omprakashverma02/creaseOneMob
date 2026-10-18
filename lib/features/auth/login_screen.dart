import 'package:flutter/material.dart';

import '../../core/config.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../widgets/common.dart';
import '../../widgets/server_settings.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() fn) async {
    setState(() => _busy = true);
    try {
      await fn();
    } catch (e) {
      if (mounted) context.toast(e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(center: Alignment(0, -0.6), radius: 1.2, colors: [Color(0xFF12275A), AppColors.bg]),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const AppLogo(height: 190),
                  const SizedBox(height: 10),
                  const Text('Score every ball like a pro',
                      textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 6),
                  const Text('Live ball-by-ball scoring, scorecards, tournaments, points tables and player stats.',
                      textAlign: TextAlign.center, style: TextStyle(color: AppColors.textMid)),
                  const SizedBox(height: 32),
                  _GoogleButton(busy: _busy, onTap: () => _run(() => context.auth.signInWithGoogle())),
                  const SizedBox(height: 14),
                  Row(children: const [
                    Expanded(child: Divider()),
                    Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('or', style: TextStyle(color: AppColors.textLo))),
                    Expanded(child: Divider()),
                  ]),
                  const SizedBox(height: 14),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _showEmailSheet(signUp: false),
                    icon: const Icon(Icons.mail_outline_rounded),
                    label: const Text('Sign in with email'),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _showScorerSheet,
                    icon: const Icon(Icons.scoreboard_outlined),
                    label: const Text('Match scorer login'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _busy ? null : () => _showEmailSheet(signUp: true),
                    child: const Text('New here? Create an account'),
                  ),
                  TextButton.icon(
                    onPressed: _busy ? null : () => context.auth.continueAsGuest(),
                    icon: const Icon(Icons.visibility_outlined, size: 18),
                    label: const Text('Browse live scores without signing in'),
                  ),
                  TextButton.icon(
                    onPressed: () => showServerSettings(context, onChanged: () => setState(() {})),
                    icon: const Icon(Icons.dns_outlined, size: 16, color: AppColors.textLo),
                    label: Text('Server: ${AppConfig.apiOrigin}', style: const TextStyle(color: AppColors.textLo, fontSize: 12)),
                  ),
                  const SizedBox(height: 24),
                  Text(AppConfig.tagline.toUpperCase(),
                      textAlign: TextAlign.center, style: const TextStyle(fontSize: 10.5, letterSpacing: 2, color: AppColors.textLo, fontWeight: FontWeight.w700)),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showEmailSheet({required bool signUp}) {
    final name = TextEditingController();
    final email = TextEditingController();
    final pass = TextEditingController();
    final phone = TextEditingController();
    String role = 'broadcaster';
    final formKey = GlobalKey<FormState>();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetCtx) => StatefulBuilder(builder: (c, setS) {
        bool busy = false;
        return Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(c).viewInsets.bottom + 20),
          child: Form(
            key: formKey,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(signUp ? 'Create account' : 'Sign in', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
              const SizedBox(height: 16),
              if (signUp) ...[
                TextFormField(controller: name, decoration: const InputDecoration(labelText: 'Full name'), validator: _req),
                const SizedBox(height: 10),
              ],
              TextFormField(
                controller: email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email'),
                validator: (v) => (v == null || !v.contains('@')) ? 'Enter a valid email' : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: pass,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Password'),
                validator: (v) => (v == null || v.length < 6) ? 'Min 6 characters' : null,
              ),
              if (signUp) ...[
                const SizedBox(height: 10),
                TextFormField(
                  controller: phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Mobile number'),
                  validator: (v) => (v == null || v.replaceAll(RegExp(r'\D'), '').length < 10) ? 'Enter a 10 digit number' : null,
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: role,
                  decoration: const InputDecoration(labelText: 'I am a'),
                  items: AuthUser.roles.entries.where((e) => e.key != 'admin').map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
                  onChanged: (v) => setS(() => role = v ?? role),
                ),
              ],
              const SizedBox(height: 18),
              FilledButton(
                onPressed: () async {
                  if (!formKey.currentState!.validate()) return;
                  if (busy) return;
                  busy = true;
                  final nav = Navigator.of(sheetCtx);
                  try {
                    if (signUp) {
                      await context.auth.signUpWithEmail(name: name.text.trim(), email: email.text, password: pass.text, role: role, contact: phone.text.trim());
                    } else {
                      await context.auth.signInWithEmail(email.text, pass.text);
                    }
                    if (nav.canPop()) nav.pop();
                  } catch (e) {
                    if (c.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: AppColors.live));
                  } finally {
                    busy = false;
                  }
                },
                child: Text(signUp ? 'Create account' : 'Sign in'),
              ),
            ]),
          ),
        );
      }),
    );
  }

  void _showScorerSheet() {
    final match = TextEditingController();
    final user = TextEditingController();
    final pass = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetCtx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(sheetCtx).viewInsets.bottom + 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Match scorer login', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          const Text('Use the match number and the scorer credentials shared by the organiser.', style: TextStyle(color: AppColors.textMid)),
          const SizedBox(height: 16),
          TextField(controller: match, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Match # (or match ID)')),
          const SizedBox(height: 10),
          TextField(controller: user, decoration: const InputDecoration(labelText: 'Scorer username')),
          const SizedBox(height: 10),
          TextField(controller: pass, obscureText: true, decoration: const InputDecoration(labelText: 'Password')),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: () async {
              final nav = Navigator.of(sheetCtx);
              try {
                await context.auth.scorerLogin(match: match.text, username: user.text, password: pass.text);
                if (nav.canPop()) nav.pop();
              } catch (e) {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: AppColors.live));
              }
            },
            child: const Text('Start scoring'),
          ),
        ]),
      ),
    );
  }

  String? _req(String? v) => (v == null || v.trim().isEmpty) ? 'Required' : null;
}

class _GoogleButton extends StatelessWidget {
  const _GoogleButton({required this.busy, required this.onTap});
  final bool busy;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF1F1F1F),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 0,
        ),
        onPressed: busy ? null : onTap,
        child: busy
            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
            : Row(mainAxisAlignment: MainAxisAlignment.center, children: const [
                _GoogleG(),
                SizedBox(width: 12),
                Text('Continue with Google', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ]),
      ),
    );
  }
}

/// Simple four-colour "G" mark drawn without an image asset.
class _GoogleG extends StatelessWidget {
  const _GoogleG();
  @override
  Widget build(BuildContext context) => SizedBox(width: 22, height: 22, child: CustomPaint(painter: _GPainter()));
}

class _GPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.2;
    final rect = Rect.fromLTWH(stroke / 2, stroke / 2, size.width - stroke, size.height - stroke);
    Paint p(Color c) => Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    const pi = 3.1415926535;
    canvas.drawArc(rect, -pi / 4, -pi / 2, false, p(const Color(0xFFEA4335)));
    canvas.drawArc(rect, -3 * pi / 4, -pi / 2, false, p(const Color(0xFFFBBC05)));
    canvas.drawArc(rect, 3 * pi / 4, -pi / 2, false, p(const Color(0xFF34A853)));
    canvas.drawArc(rect, pi / 4, -pi / 4, false, p(const Color(0xFF4285F4)));
    canvas.drawLine(Offset(size.width / 2, size.height / 2), Offset(size.width - stroke / 2, size.height / 2), p(const Color(0xFF4285F4)));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
