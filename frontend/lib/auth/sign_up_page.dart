import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import '../config/api_config.dart';
import '../services/language_service.dart';

class SignUpPage extends StatefulWidget {
  const SignUpPage({super.key});
  @override
  State<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController       = TextEditingController();
  final TextEditingController _emailController      = TextEditingController();
  final TextEditingController _passwordController   = TextEditingController();
  final TextEditingController _phoneController      = TextEditingController();
  final TextEditingController _chifaCardController  = TextEditingController();
  final TextEditingController _dateOfBirthController = TextEditingController();
  String? _selectedSkillLevel;
  bool _isLoading       = false;
  bool _isScanningChifa = false;
  bool _obscurePassword = true;
    bool _hasMinLength   = false;
  bool _hasUppercase   = false;
  bool _hasLowercase   = false;
  bool _hasNumber      = false;
  bool _hasSpecialChar = false;

  late AnimationController _animCtrl;
  late Animation<double>   _fadeAnim;
  late Animation<Offset>   _slideAnim;

  static const Color primary  = Color(0xFF1565C0);
  static const Color accent   = Color(0xFF64B5F6);
  static const Color darkText = Color(0xFF0F172A);

  @override
  void initState() {
    super.initState();
    _animCtrl  = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    _fadeAnim  = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero)
        .animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic));
     _passwordController.addListener(_checkStrength);
    _animCtrl.forward();
  }

  void _checkStrength() {
    final p = _passwordController.text;
    setState(() {
      _hasMinLength   = p.length >= 8;
      _hasUppercase   = RegExp(r'[A-Z]').hasMatch(p);
      _hasLowercase   = RegExp(r'[a-z]').hasMatch(p);
      _hasNumber      = RegExp(r'[0-9]').hasMatch(p);
      _hasSpecialChar = RegExp(r'[!@#\$%^&*()_+\-=\[\]{};:"\\|,.<>\/?]').hasMatch(p);
    });
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _phoneController.dispose();
    _chifaCardController.dispose();
    _dateOfBirthController.dispose();
    super.dispose();
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().subtract(const Duration(days: 365 * 20)),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(primary: primary),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _dateOfBirthController.text =
            '${picked.day.toString().padLeft(2, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.year}';
      });
    }
  }

  Future<void> _scanChifaCard() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
      maxWidth: 1600,
    );
    if (pickedFile == null) return;
    if (!mounted) return;

    setState(() => _isScanningChifa = true);
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${ApiConfig.baseUrl}/auth/scan-chifa'),
      );
      request.files.add(await http.MultipartFile.fromPath('card', pickedFile.path));

      final streamedResponse = await request.send().timeout(const Duration(seconds: 30));
      final response = await http.Response.fromStream(streamedResponse);
      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        setState(() => _chifaCardController.text = data['scrnNumber']);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(data['message'] ?? 'Could not read your Chifa card'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error scanning card: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _isScanningChifa = false);
    }
  }

  Future<void> _signUp() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedSkillLevel == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Please select your smartphone skill level'),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    setState(() => _isLoading = true);
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/auth/register'),
        headers: ApiConfig.headers,
        body: jsonEncode({
          'name':                       _nameController.text.trim(),
          'email':                      _emailController.text.trim(),
          'password':                   _passwordController.text,
          'phone':                      _phoneController.text.trim(),
          'chifaCardRegistrationNumber': _chifaCardController.text.trim(),
          'dateOfBirth':                _dateOfBirthController.text,
          'smartphoneSkillLevel':       _selectedSkillLevel,
        }),
      ).timeout(const Duration(seconds: 20));

      final data = jsonDecode(response.body);
if (response.statusCode == 201 && data['success'] == true) {
  // Don't save token or navigate to app — show verification message instead
  if (mounted) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('Check your email'),
        content: const Text(
          'A verification link has been sent to your email address. '
          'Please verify your account before logging in.'
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.pushReplacementNamed(context, '/signin');
            },
            child: const Text('Go to Login'),
          ),
        ],
      ),
    );
  }
}else {
        throw Exception(data['message'] ?? 'Registration failed');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('❌ $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<LanguageService>(context);
    return Scaffold(
      backgroundColor: primary,
      body: Stack(children: [
        Positioned(top: -60, right: -60,
          child: Container(width: 220, height: 220,
            decoration: BoxDecoration(shape: BoxShape.circle,
                color: accent.withOpacity(0.1)))),
        Positioned(bottom: 300, left: -60,
          child: Container(width: 160, height: 160,
            decoration: BoxDecoration(shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.03)))),

        SafeArea(child: Column(children: [

          // header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 28, 20),
            child: FadeTransition(opacity: _fadeAnim,
              child: Row(children: [
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: 42, height: 42,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 20),
                  ),
                ),
                const SizedBox(width: 16),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Create Account', style: TextStyle(color: Colors.white,
                      fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: -0.3)),
                  Text('Join MediCare today', style: TextStyle(
                      color: Colors.white.withOpacity(0.55), fontSize: 13)),
                ]),
              ]),
            ),
          ),

          // white card
          Expanded(child: FadeTransition(opacity: _fadeAnim,
            child: SlideTransition(position: _slideAnim,
              child: Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(36), topRight: Radius.circular(36)),
                ),
                child: Form(
                  key: _formKey,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(28, 32, 28, 32),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

                      // section: personal
                      _sectionHeader('Personal Information', Icons.person_outline_rounded),
                      const SizedBox(height: 16),

                      _label(lang.translate('profile')),
                      const SizedBox(height: 8),
                      _formField(
                        controller: _nameController,
                        hint: 'Your full name',
                        icon: Icons.person_outline_rounded,
                        validator: (v) => (v == null || v.isEmpty) ? 'Name is required' : null,
                      ),
                      const SizedBox(height: 14),

                      _label(lang.translate('email')),
                      const SizedBox(height: 8),
                      _formField(
                        controller: _emailController,
                        hint: 'email@example.com',
                        icon: Icons.mail_outline_rounded,
                        keyboardType: TextInputType.emailAddress,
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Email is required';
                          if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(v)) return 'Invalid email format';
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),

                      _label(lang.translate('password')),
                      const SizedBox(height: 8),
                      _formField(
                        controller: _passwordController,
                        hint: 'Min 8 chars, A-Z, 0-9, !@#...',
                        icon: Icons.lock_outline_rounded,
                        obscure: _obscurePassword,
                        suffixIcon: IconButton(
                          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                          icon: Icon(_obscurePassword
                              ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                              color: Colors.grey.shade400, size: 20),
                        ),
                      validator: (v) {
  if (v == null || v.isEmpty) return 'Password is required';
  if (v.length < 8) return 'At least 8 characters';
  if (!RegExp(r'[A-Z]').hasMatch(v)) return 'At least one uppercase letter';
  if (!RegExp(r'[a-z]').hasMatch(v)) return 'At least one lowercase letter';
  if (!RegExp(r'[0-9]').hasMatch(v)) return 'At least one number';
  if (!RegExp(r'[!@#\$%^&*()_+\-=\[\]{};:"\\|,.<>\/?]').hasMatch(v))
    return 'At least one special character (!@#\$%^&*)';
  return null;
},
                      ),
                                            const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Text('Password requirements',
                              style: TextStyle(fontWeight: FontWeight.bold,
                                  color: primary, fontSize: 12)),
                          const SizedBox(height: 10),
                          _criterion('At least 8 characters',          _hasMinLength),
                          _criterion('At least one uppercase letter',  _hasUppercase),
                          _criterion('At least one lowercase letter',  _hasLowercase),
                          _criterion('At least one number',            _hasNumber),
                          _criterion('At least one special character', _hasSpecialChar),
                        ]),
                      ),

                      const SizedBox(height: 14),

                      _label(lang.translate('phone')),
                      const SizedBox(height: 8),
                      _formField(
                        controller: _phoneController,
                        hint: '0612345678',
                        icon: Icons.phone_outlined,
                        keyboardType: TextInputType.phone,
                        validator: (v) => (v == null || v.length != 10)
                            ? 'Phone must be 10 digits' : null,
                      ),
                      const SizedBox(height: 28),

                      // section: medical
                      _sectionHeader('Medical Information', Icons.medical_information_outlined),
                      const SizedBox(height: 16),

                      _label(lang.translate('chifaNumber')),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _chifaCardController,
                        readOnly: true,
                        onTap: _isScanningChifa ? null : _scanChifaCard,
                        style: const TextStyle(fontSize: 15, color: darkText),
                        validator: (v) => (v == null || v.length != 12)
                            ? 'Please scan your Chifa card for confirmation' : null,
                        decoration: InputDecoration(
                          hintText: 'Please scan your chifa card for confirmation',
                          hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                          prefixIcon: Icon(Icons.card_membership_outlined, color: Colors.grey.shade400, size: 20),
                          suffixIcon: _isScanningChifa
                              ? const Padding(
                                  padding: EdgeInsets.all(14),
                                  child: SizedBox(width: 18, height: 18,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: primary)),
                                )
                              : IconButton(
                                  onPressed: _scanChifaCard,
                                  icon: const Icon(Icons.camera_alt_outlined, color: primary, size: 20),
                                ),
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: Colors.grey.shade200),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: primary, width: 1.5),
                          ),
                          errorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: Colors.red),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),

                      _label(lang.translate('dateOfBirth')),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _dateOfBirthController,
                        readOnly: true,
                        onTap: () => _selectDate(context),
                        style: const TextStyle(fontSize: 15, color: darkText),
                        validator: (v) => (v == null || v.isEmpty) ? 'Date of birth is required' : null,
                        decoration: InputDecoration(
                          hintText: 'DD-MM-YYYY',
                          hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                          prefixIcon: Icon(Icons.calendar_today_outlined,
                              color: Colors.grey.shade400, size: 20),
                          suffixIcon: Icon(Icons.arrow_drop_down_rounded,
                              color: Colors.grey.shade400),
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: Colors.grey.shade200),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: primary, width: 1.5),
                          ),
                          errorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: Colors.red),
                          ),
                          focusedErrorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: Colors.red, width: 1.5),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),

                      _label(lang.translate('skillLevel')),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: _selectedSkillLevel,
                        isExpanded: true,
                        style: const TextStyle(fontSize: 15, color: darkText),
                        decoration: InputDecoration(
                          hintText: 'Select your level',
                          prefixIcon: Icon(Icons.smartphone_outlined,
                              color: Colors.grey.shade400, size: 20),
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: Colors.grey.shade200),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: primary, width: 1.5),
                          ),
                          errorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: Colors.red),
                          ),
                          focusedErrorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: Colors.red, width: 1.5),
                          ),
                        ),
                        items: [
                          DropdownMenuItem(value: 'BASIC',
                              child: Text(lang.translate('basic'))),
                          DropdownMenuItem(value: 'INTERMEDIATE',
                              child: Text(lang.translate('intermediate'))),
                          DropdownMenuItem(value: 'ADVANCED',
                              child: Text(lang.translate('advanced'))),
                        ],
                        onChanged: (v) => setState(() => _selectedSkillLevel = v),
                        validator: (v) => v == null ? 'Please select your skill level' : null,
                      ),
                      const SizedBox(height: 32),

                      // register button
                      SizedBox(
                        width: double.infinity, height: 56,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _signUp,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primary, foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          child: _isLoading
                              ? const SizedBox(width: 22, height: 22,
                                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                              : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                                  Text(lang.translate('signUp'), style: const TextStyle(
                                      fontSize: 17, fontWeight: FontWeight.bold, letterSpacing: 0.2)),
                                  const SizedBox(width: 8),
                                  const Icon(Icons.arrow_forward_rounded, size: 20),
                                ]),
                        ),
                      ),
                      const SizedBox(height: 20),

                      Center(child: Wrap(alignment: WrapAlignment.center, spacing: 4, children: [
                        Text(lang.translate('alreadyHaveAccount'),
                            style: TextStyle(color: Colors.grey.shade500, fontSize: 14)),
                        GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: Text(lang.translate('signIn'),
                              style: const TextStyle(color: primary,
                                  fontWeight: FontWeight.bold, fontSize: 14)),
                        ),
                      ])),
                    ]),
                  ),
                ),
              ),
            ),
          )),
        ])),
      ]),
    );
  }

  Widget _sectionHeader(String title, IconData icon) {
    return Row(children: [
      Container(
        width: 34, height: 34,
        decoration: BoxDecoration(color: primary.withOpacity(0.08), borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, color: primary, size: 18),
      ),
      const SizedBox(width: 10),
      Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800,
          color: darkText, letterSpacing: -0.2)),
    ]);
  }

  Widget _label(String text) => Text(text, style: const TextStyle(
      fontSize: 13, fontWeight: FontWeight.w600, color: darkText));

  Widget _formField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool obscure = false,
    TextInputType? keyboardType,
    Widget? suffixIcon,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      validator: validator,
      style: const TextStyle(fontSize: 15, color: darkText),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
        prefixIcon: Icon(icon, color: Colors.grey.shade400, size: 20),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.red),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.red, width: 1.5),
        ),
      ),
    );
  }
  Widget _criterion(String text, bool met) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Icon(met ? Icons.check_circle_rounded : Icons.circle_outlined,
            size: 15,
            color: met ? Colors.green.shade500 : Colors.grey.shade400),
        const SizedBox(width: 8),
        Text(text, style: TextStyle(
            fontSize: 12,
            color: met ? Colors.green.shade700 : Colors.grey.shade600,
            decoration: met ? TextDecoration.lineThrough : null)),
      ]),
    );
  }
}