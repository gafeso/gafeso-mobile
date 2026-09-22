import 'package:flutter/material.dart';

/// Écran 2 — **connexion** (email + mot de passe) dans l'école choisie. Le jeton et l'identité
/// sont ensuite conservés dans une session **chiffrée localement** (clé du keystore), ce qui
/// permet de lire hors-ligne et alimente le filigrane.
///
/// Le rafraîchissement de jeton est **reporté** (décision backend) : à l'expiration, l'usager
/// se reconnecte.
class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    required this.tenantSlug,
    required this.onLogin,
    required this.onChangeTenant,
    this.notice,
  });

  /// Avis à présenter AVANT toute saisie — typiquement une session expirée.
  /// Distinct de l'erreur de saisie : il explique pourquoi on est ici, et il
  /// n'accuse pas les identifiants, qui n'ont rien fait de mal.
  final String? notice;

  final String tenantSlug;
  final Future<String?> Function({required String email, required String password}) onLogin;
  final Future<void> Function() onChangeTenant;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  String? _error;
  bool _busy = false;
  bool _obscure = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_email.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() => _error = 'Renseignez votre email et votre mot de passe.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await widget.onLogin(email: _email.text.trim(), password: _password.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = err;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Connexion · ${widget.tenantSlug}')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: ListView(
              padding: const EdgeInsets.all(24),
              shrinkWrap: true,
              children: [
                if (widget.notice != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      border: Border(
                        left: BorderSide(color: Colors.amber.shade700, width: 3),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.schedule, size: 18, color: Colors.amber.shade900),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            widget.notice!,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
                TextField(
                  controller: _email,
                  enabled: !_busy,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.alternate_email),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _password,
                  enabled: !_busy,
                  obscureText: _obscure,
                  textInputAction: TextInputAction.go,
                  onSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    labelText: 'Mot de passe',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _busy ? null : _submit,
                  icon: _busy
                      ? const SizedBox(
                          width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.login),
                  label: Text(_busy ? 'Connexion…' : 'Se connecter'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _busy ? null : widget.onChangeTenant,
                  child: const Text('Changer d’école'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
