import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _fullNameController =
  TextEditingController();

  final TextEditingController _emailController =
  TextEditingController();

  final TextEditingController _vehicleNumberController =
  TextEditingController();

  final TextEditingController _passwordController =
  TextEditingController();

  final TextEditingController _confirmPasswordController =
  TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _fullNameController.dispose();
    _emailController.dispose();
    _vehicleNumberController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();

    super.dispose();
  }

  // ============================================================
  // FIREBASE SIGN UP
  // ============================================================

  Future<void> _signUp() async {
    FocusScope.of(context).unfocus();

    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final String fullName =
      _fullNameController.text.trim();

      final String email =
      _emailController.text.trim();

      final String password =
          _passwordController.text;

      // Create Firebase Authentication account
      final UserCredential credential =
      await FirebaseAuth.instance
          .createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Save driver's name to Firebase Auth profile
      await credential.user?.updateDisplayName(fullName);

      if (!mounted) return;

      _showMessage(
        'Account created successfully!',
        isError: false,
      );

      // ========================================================
      // NAVIGATE AFTER SUCCESSFUL REGISTRATION
      // ========================================================
      //
      // Example:
      //
      // Navigator.pushReplacement(
      //   context,
      //   MaterialPageRoute(
      //     builder: (_) => const DashboardPage(),
      //   ),
      // );
      //
      // ========================================================
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;

      String message;

      switch (e.code) {
        case 'email-already-in-use':
          message =
          'An account already exists with this email.';
          break;

        case 'invalid-email':
          message =
          'Please enter a valid email address.';
          break;

        case 'weak-password':
          message =
          'Password is too weak. Use a stronger password.';
          break;

        case 'operation-not-allowed':
          message =
          'Email/password authentication is not enabled in Firebase.';
          break;

        case 'network-request-failed':
          message =
          'Network error. Check your internet connection.';
          break;

        default:
          message = e.message ??
              'Unable to create your account. Please try again.';
      }

      _showMessage(
        message,
        isError: true,
      );
    } catch (e) {
      if (!mounted) return;

      _showMessage(
        'Something went wrong. Please try again.',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // ============================================================
  // SNACKBAR
  // ============================================================

  void _showMessage(
      String message, {
        required bool isError,
      }) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                isError
                    ? Icons.error_outline_rounded
                    : Icons.check_circle_outline_rounded,
                color: Colors.white,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          backgroundColor: isError
              ? const Color(0xFFDC2626)
              : const Color(0xFF16A34A),
        ),
      );
  }

  // ============================================================
  // INPUT DECORATION
  // ============================================================

  InputDecoration _inputDecoration({
    required String hintText,
    required IconData icon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      hintText: hintText,

      prefixIcon: Icon(
        icon,
        size: 21,
        color: const Color(0xFF9AA2B1),
      ),

      suffixIcon: suffixIcon,

      filled: true,
      fillColor: Colors.white,

      contentPadding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 17,
      ),

      hintStyle: const TextStyle(
        color: Color(0xFF9AA2B1),
        fontSize: 14.5,
      ),

      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(
          color: Color(0xFFD9DEE8),
        ),
      ),

      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(
          color: Color(0xFFD9DEE8),
        ),
      ),

      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(
          color: Color(0xFF2563EB),
          width: 1.7,
        ),
      ),

      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(
          color: Color(0xFFDC2626),
        ),
      ),

      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(
          color: Color(0xFFDC2626),
          width: 1.5,
        ),
      ),
    );
  }

  // ============================================================
  // FIELD LABEL
  // ============================================================

  Widget _fieldLabel(
      String text, {
        bool optional = false,
      }) {
    return Row(
      children: [
        Text(
          text.toUpperCase(),
          style: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.2,
            color: Color(0xFF4B5563),
          ),
        ),

        if (optional) ...[
          const SizedBox(width: 4),

          const Text(
            '(optional)',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: Color(0xFF9AA2B1),
            ),
          ),
        ],
      ],
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F7F4),

      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 28,
            ),

            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: 440,
              ),

              child: Column(
                children: [
                  // ==================================================
                  // TITLE
                  // ==================================================

                  const Text(
                    'Create Account',
                    textAlign: TextAlign.center,

                    style: TextStyle(
                      fontSize: 29,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.7,
                      color: Color(0xFF111827),
                    ),
                  ),

                  const SizedBox(height: 7),

                  const Text(
                    'Enter your credentials to register as a driver.',
                    textAlign: TextAlign.center,

                    style: TextStyle(
                      fontSize: 14.5,
                      color: Color(0xFF6B7280),
                      fontWeight: FontWeight.w500,
                    ),
                  ),

                  const SizedBox(height: 28),

                  // ==================================================
                  // REGISTER CARD
                  // ==================================================

                  Container(
                    width: double.infinity,

                    padding: const EdgeInsets.fromLTRB(
                      20,
                      22,
                      20,
                      20,
                    ),

                    decoration: BoxDecoration(
                      color: Colors.white,

                      borderRadius:
                      BorderRadius.circular(20),

                      border: Border.all(
                        color: const Color(0xFFE5E7EB),
                      ),

                      boxShadow: [
                        BoxShadow(
                          color:
                          Colors.black.withOpacity(0.045),
                          blurRadius: 25,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),

                    child: Form(
                      key: _formKey,

                      child: Column(
                        crossAxisAlignment:
                        CrossAxisAlignment.start,

                        children: [
                          // ==================================================
                          // FULL NAME
                          // ==================================================

                          _fieldLabel('Full Name'),

                          const SizedBox(height: 7),

                          TextFormField(
                            controller:
                            _fullNameController,

                            textCapitalization:
                            TextCapitalization.words,

                            textInputAction:
                            TextInputAction.next,

                            decoration:
                            _inputDecoration(
                              hintText: 'John Doe',

                              icon: Icons
                                  .person_outline_rounded,
                            ),

                            validator: (value) {
                              if (value == null ||
                                  value.trim().isEmpty) {
                                return 'Please enter your full name';
                              }

                              if (value.trim().length < 2) {
                                return 'Please enter a valid name';
                              }

                              return null;
                            },
                          ),

                          const SizedBox(height: 15),

                          // ==================================================
                          // EMAIL
                          // ==================================================

                          _fieldLabel('Email'),

                          const SizedBox(height: 7),

                          TextFormField(
                            controller:
                            _emailController,

                            keyboardType:
                            TextInputType.emailAddress,

                            textInputAction:
                            TextInputAction.next,

                            autocorrect: false,

                            decoration:
                            _inputDecoration(
                              hintText:
                              'driver@example.com',

                              icon: Icons
                                  .email_outlined,
                            ),

                            validator: (value) {
                              if (value == null ||
                                  value.trim().isEmpty) {
                                return 'Please enter your email';
                              }

                              final emailRegex =
                              RegExp(
                                r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                              );

                              if (!emailRegex.hasMatch(
                                value.trim(),
                              )) {
                                return 'Please enter a valid email';
                              }

                              return null;
                            },
                          ),

                          const SizedBox(height: 15),

                          // ==================================================
                          // VEHICLE NUMBER
                          // ==================================================

                          _fieldLabel(
                            'Vehicle Number',
                            optional: true,
                          ),

                          const SizedBox(height: 7),

                          TextFormField(
                            controller:
                            _vehicleNumberController,

                            textCapitalization:
                            TextCapitalization.characters,

                            textInputAction:
                            TextInputAction.next,

                            decoration:
                            _inputDecoration(
                              hintText: 'ABC-1234',

                              icon: Icons
                                  .directions_car_outlined,
                            ),
                          ),

                          const SizedBox(height: 15),

                          // ==================================================
                          // PASSWORD
                          // ==================================================

                          _fieldLabel('Password'),

                          const SizedBox(height: 7),

                          TextFormField(
                            controller:
                            _passwordController,

                            obscureText:
                            _obscurePassword,

                            textInputAction:
                            TextInputAction.next,

                            decoration:
                            _inputDecoration(
                              hintText:
                              'Enter your password',

                              icon: Icons
                                  .lock_outline_rounded,

                              suffixIcon:
                              IconButton(
                                tooltip:
                                _obscurePassword
                                    ? 'Show password'
                                    : 'Hide password',

                                onPressed: () {
                                  setState(() {
                                    _obscurePassword =
                                    !_obscurePassword;
                                  });
                                },

                                icon: Icon(
                                  _obscurePassword
                                      ? Icons
                                      .visibility_outlined
                                      : Icons
                                      .visibility_off_outlined,

                                  size: 21,

                                  color:
                                  const Color(
                                    0xFF9AA2B1,
                                  ),
                                ),
                              ),
                            ),

                            validator: (value) {
                              if (value == null ||
                                  value.isEmpty) {
                                return 'Please enter a password';
                              }

                              if (value.length < 6) {
                                return 'Password must be at least 6 characters';
                              }

                              return null;
                            },
                          ),

                          const SizedBox(height: 15),

                          // ==================================================
                          // CONFIRM PASSWORD
                          // ==================================================

                          _fieldLabel(
                            'Confirm Password',
                          ),

                          const SizedBox(height: 7),

                          TextFormField(
                            controller:
                            _confirmPasswordController,

                            obscureText:
                            _obscureConfirmPassword,

                            textInputAction:
                            TextInputAction.done,

                            onFieldSubmitted: (_) {
                              if (!_isLoading) {
                                _signUp();
                              }
                            },

                            decoration:
                            _inputDecoration(
                              hintText:
                              'Re-enter your password',

                              icon: Icons
                                  .lock_outline_rounded,

                              suffixIcon:
                              IconButton(
                                tooltip:
                                _obscureConfirmPassword
                                    ? 'Show password'
                                    : 'Hide password',

                                onPressed: () {
                                  setState(() {
                                    _obscureConfirmPassword =
                                    !_obscureConfirmPassword;
                                  });
                                },

                                icon: Icon(
                                  _obscureConfirmPassword
                                      ? Icons
                                      .visibility_outlined
                                      : Icons
                                      .visibility_off_outlined,

                                  size: 21,

                                  color:
                                  const Color(
                                    0xFF9AA2B1,
                                  ),
                                ),
                              ),
                            ),

                            validator: (value) {
                              if (value == null ||
                                  value.isEmpty) {
                                return 'Please confirm your password';
                              }

                              if (value !=
                                  _passwordController.text) {
                                return 'Passwords do not match';
                              }

                              return null;
                            },
                          ),

                          const SizedBox(height: 23),

                          // ==================================================
                          // SIGN UP BUTTON
                          // ==================================================

                          SizedBox(
                            width: double.infinity,
                            height: 54,

                            child: ElevatedButton(
                              onPressed:
                              _isLoading
                                  ? null
                                  : _signUp,

                              style:
                              ElevatedButton.styleFrom(
                                backgroundColor:
                                const Color(
                                  0xFF2563EB,
                                ),

                                foregroundColor:
                                Colors.white,

                                disabledBackgroundColor:
                                const Color(
                                  0xFF93B4F4,
                                ),

                                elevation: 0,

                                shape:
                                RoundedRectangleBorder(
                                  borderRadius:
                                  BorderRadius.circular(
                                    12,
                                  ),
                                ),
                              ),

                              child: AnimatedSwitcher(
                                duration:
                                const Duration(
                                  milliseconds: 180,
                                ),

                                child: _isLoading
                                    ? const SizedBox(
                                  key: ValueKey(
                                    'loading',
                                  ),

                                  width: 23,
                                  height: 23,

                                  child:
                                  CircularProgressIndicator(
                                    strokeWidth: 2.5,

                                    valueColor:
                                    AlwaysStoppedAnimation<
                                        Color>(
                                      Colors.white,
                                    ),
                                  ),
                                )
                                    : const Text(
                                  'SIGN UP',

                                  key: ValueKey(
                                    'signup',
                                  ),

                                  style: TextStyle(
                                    fontSize: 16,

                                    fontWeight:
                                    FontWeight.w800,

                                    letterSpacing: 0.3,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 22),

                  // ==================================================
                  // SIGN IN
                  // ==================================================

                  Row(
                    mainAxisAlignment:
                    MainAxisAlignment.center,

                    children: [
                      const Text(
                        'Already have an account? ',

                        style: TextStyle(
                          fontSize: 14,
                          color: Color(0xFF6B7280),
                        ),
                      ),

                      GestureDetector(
                        onTap: () {
                          Navigator.pop(context);
                        },

                        child: const Text(
                          'Sign In',

                          style: TextStyle(
                            fontSize: 14,
                            fontWeight:
                            FontWeight.w700,
                            color: Color(0xFF2563EB),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 15),

                  // ==================================================
                  // SECURITY MESSAGE
                  // ==================================================

                  Row(
                    mainAxisAlignment:
                    MainAxisAlignment.center,

                    children: [
                      Icon(
                        Icons
                            .verified_user_outlined,

                        size: 14,

                        color:
                        Colors.grey.shade500,
                      ),

                      const SizedBox(width: 6),

                      Text(
                        'Your account is securely protected',

                        style: TextStyle(
                          fontSize: 11.5,
                          color:
                          Colors.grey.shade500,
                        ),
                      ),
                    ],
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