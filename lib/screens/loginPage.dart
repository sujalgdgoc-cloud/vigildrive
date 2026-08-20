import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:vigil_drive/screens/homePage.dart';

import 'package:vigil_drive/screens/signUp.dart';
import 'forgotPass.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _emailController =
  TextEditingController();

  final TextEditingController _passwordController =
  TextEditingController();

  final TextEditingController _truckIdController =
  TextEditingController();

  bool _obscurePassword = true;
  bool _isLoading = false;

  // ============================================================
  // DJANGO API URL
  // ============================================================
  //
  // Replace this with your actual Django API endpoint.
  //
  // Example:
  // static const String djangoApiUrl =
  //     'https://your-domain.com/api/trucks/';
  //
  // IMPORTANT:
  // The API should return the list containing objects like:
  //
  // {
  //   "id": 1,
  //   "driver": "Ramesh",
  //   "truck_id": "TCK-383",
  //   "truck_no": "HR-J748-8573",
  //   ...
  // }
  //
  static const String djangoApiUrl =
      'https://vigildrivebackend.onrender.com/api/v2/driverinfo/?format=json';

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _truckIdController.dispose();
    super.dispose();
  }

  // ============================================================
  // VERIFY TRUCK ID FROM DJANGO
  // ============================================================

  Future<bool> _verifyTruckId(String truckId) async {
    try {
      final response = await http.get(
        Uri.parse(djangoApiUrl),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode != 200) {
        if (mounted) {
          _showMessage(
            'Unable to verify Truck ID. Please try again.',
            isError: true,
          );
        }

        return false;
      }

      final dynamic data = jsonDecode(response.body);

      // ========================================================
      // EXPECTED RESPONSE:
      //
      // [
      //   {
      //     "id": 1,
      //     "driver": "Ramesh",
      //     "truck_id": "TCK-383",
      //     ...
      //   }
      // ]
      //
      // ========================================================

      if (data is! List) {
        if (mounted) {
          _showMessage(
            'Invalid response received from server.',
            isError: true,
          );
        }

        return false;
      }

      final String enteredTruckId =
      truckId.trim().toLowerCase();

      // ========================================================
      // ONLY MATCH truck_id
      // ========================================================

      for (final item in data) {
        if (item is Map<String, dynamic>) {
          final dynamic apiTruckId = item['truck_id'];

          if (apiTruckId != null &&
              apiTruckId.toString().trim().toLowerCase() ==
                  enteredTruckId) {
            return true;
          }
        }
      }

      // Truck ID was not found
      if (mounted) {
        _showMessage(
          'Truck ID not found. Please enter a valid Truck ID.',
          isError: true,
        );
      }

      return false;
    } catch (e) {
      if (mounted) {
        _showMessage(
          'Unable to connect to the server. Check your internet connection.',
          isError: true,
        );
      }

      return false;
    }
  }

  // ============================================================
  // FIREBASE LOGIN
  // ============================================================

  Future<void> _login() async {
    FocusScope.of(context).unfocus();

    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final String email =
      _emailController.text.trim();

      final String password =
          _passwordController.text;

      final String truckId =
      _truckIdController.text.trim();

      // ========================================================
      // STEP 1:
      // VERIFY TRUCK ID WITH DJANGO FIRST
      // ========================================================

      final bool truckIdValid =
      await _verifyTruckId(truckId);

      if (!truckIdValid) {
        return;
      }

      // ========================================================
      // STEP 2:
      // FIREBASE EMAIL/PASSWORD LOGIN
      // ========================================================

      await FirebaseAuth.instance
          .signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (!mounted) return;

      _showMessage(
        'Welcome back!',
        isError: false,
      );

      // ========================================================
      // LOGIN SUCCESS
      // ========================================================
      //
      // At this point:
      //
      // 1. Truck ID exists in Django
      // 2. Firebase email exists
      // 3. Firebase password is correct
      //
      // You can navigate to your dashboard here.
      //
      // Example:
      //
      Navigator.pushReplacement(
         context,
         MaterialPageRoute(
           builder: (_) => DriverHomePage(truckId: truckId),
         ),
       );
      
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;

      String message;

      switch (e.code) {
        case 'invalid-credential':
        case 'invalid-login-credentials':
          message = 'Incorrect email or password.';
          break;

        case 'user-not-found':
          message = 'No account found with this email.';
          break;

        case 'wrong-password':
          message = 'Incorrect password.';
          break;

        case 'invalid-email':
          message = 'Please enter a valid email address.';
          break;

        case 'user-disabled':
          message = 'This account has been disabled.';
          break;

        case 'too-many-requests':
          message =
          'Too many login attempts. Try again later.';
          break;

        case 'network-request-failed':
          message =
          'Network error. Check your internet connection.';
          break;

        default:
          message =
              e.message ??
                  'Unable to sign in. Please try again.';
      }

      _showMessage(
        message,
        isError: true,
      );
    } catch (_) {
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
  // LOGO
  // ============================================================

  Widget _buildLogo() {
    return Container(
      width: 62,
      height: 62,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF2563EB),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2563EB)
                .withOpacity(0.20),
            blurRadius: 18,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: const Center(
        child: Icon(
          Icons.directions_car_filled_rounded,
          color: Colors.white,
          size: 30,
        ),
      ),
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
              vertical: 32,
            ),

            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: 440,
              ),

              child: Column(
                children: [
                  // ==================================================
                  // LOGO
                  // ==================================================

                  _buildLogo(),

                  const SizedBox(height: 20),

                  const Text(
                    'VigilDrive',
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.8,
                      color: Color(0xFF111827),
                    ),
                  ),

                  const SizedBox(height: 7),

                  const Text(
                    'Secure Driver Authentication',
                    style: TextStyle(
                      fontSize: 14.5,
                      color: Color(0xFF6B7280),
                      fontWeight: FontWeight.w500,
                    ),
                  ),

                  const SizedBox(height: 30),

                  // ==================================================
                  // LOGIN CARD
                  // ==================================================

                  Container(
                    width: double.infinity,

                    padding: const EdgeInsets.fromLTRB(
                      22,
                      24,
                      22,
                      22,
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
                          Colors.black.withOpacity(0.055),
                          blurRadius: 30,
                          offset: const Offset(0, 12),
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
                          // WELCOME
                          // ==================================================

                          const Text(
                            'Welcome back',
                            style: TextStyle(
                              fontSize: 21,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF111827),
                            ),
                          ),

                          const SizedBox(height: 5),

                          const Text(
                            'Sign in to continue to your driver account.',
                            style: TextStyle(
                              fontSize: 13.5,
                              height: 1.4,
                              color: Color(0xFF6B7280),
                            ),
                          ),

                          const SizedBox(height: 25),

                          // ==================================================
                          // EMAIL
                          // ==================================================

                          const Text(
                            'Email',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF374151),
                            ),
                          ),

                          const SizedBox(height: 8),

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
                              'Enter your email',
                              icon:
                              Icons.email_outlined,
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

                          const SizedBox(height: 19),

                          // ==================================================
                          // TRUCK ID
                          // ==================================================

                          const Text(
                            'Truck ID',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF374151),
                            ),
                          ),

                          const SizedBox(height: 8),

                          TextFormField(
                            controller:
                            _truckIdController,

                            keyboardType:
                            TextInputType.text,

                            textCapitalization:
                            TextCapitalization.characters,

                            textInputAction:
                            TextInputAction.next,

                            autocorrect: false,

                            decoration:
                            _inputDecoration(
                              hintText:
                              'Enter your Truck ID',
                              icon:
                              Icons.local_shipping_outlined,
                            ),

                            validator: (value) {
                              if (value == null ||
                                  value.trim().isEmpty) {
                                return 'Please enter your Truck ID';
                              }

                              return null;
                            },
                          ),

                          const SizedBox(height: 19),

                          // ==================================================
                          // PASSWORD + FORGOT PASSWORD
                          // ==================================================

                          Row(
                            mainAxisAlignment:
                            MainAxisAlignment.spaceBetween,

                            children: [
                              const Text(
                                'Password',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight:
                                  FontWeight.w700,
                                  color:
                                  Color(0xFF374151),
                                ),
                              ),

                              // ==================================================
                              // FORGOT PASSWORD REDIRECT
                              // ==================================================

                              GestureDetector(
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                      const ForgotPasswordPage(),
                                    ),
                                  );
                                },

                                child: const Text(
                                  'Forgot password?',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight:
                                    FontWeight.w700,
                                    color:
                                    Color(0xFF2563EB),
                                  ),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 8),

                          // ==================================================
                          // PASSWORD
                          // ==================================================

                          TextFormField(
                            controller:
                            _passwordController,

                            obscureText:
                            _obscurePassword,

                            textInputAction:
                            TextInputAction.done,

                            onFieldSubmitted: (_) {
                              if (!_isLoading) {
                                _login();
                              }
                            },

                            decoration:
                            _inputDecoration(
                              hintText:
                              'Enter your password',

                              icon:
                              Icons.lock_outline_rounded,

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
                                return 'Please enter your password';
                              }

                              if (value.length < 6) {
                                return 'Password must be at least 6 characters';
                              }

                              return null;
                            },
                          ),

                          const SizedBox(height: 25),

                          // ==================================================
                          // SIGN IN BUTTON
                          // ==================================================

                          SizedBox(
                            width: double.infinity,
                            height: 54,

                            child: ElevatedButton(
                              onPressed:
                              _isLoading
                                  ? null
                                  : _login,

                              style:
                              ElevatedButton.styleFrom(
                                backgroundColor:
                                const Color(0xFF2563EB),

                                foregroundColor:
                                Colors.white,

                                disabledBackgroundColor:
                                const Color(0xFF93B4F4),

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
                                    : const Row(
                                  key: ValueKey(
                                    'login',
                                  ),

                                  mainAxisAlignment:
                                  MainAxisAlignment
                                      .center,

                                  children: [
                                    Text(
                                      'SIGN IN',
                                      style:
                                      TextStyle(
                                        fontSize: 16,
                                        fontWeight:
                                        FontWeight
                                            .w800,
                                        letterSpacing:
                                        0.3,
                                      ),
                                    ),

                                    SizedBox(
                                      width: 9,
                                    ),

                                    Icon(
                                      Icons
                                          .arrow_forward_rounded,
                                      size: 20,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // ==================================================
                  // CREATE ACCOUNT
                  // ==================================================

                  Row(
                    mainAxisAlignment:
                    MainAxisAlignment.center,

                    children: [
                      const Text(
                        'New driver? ',
                        style: TextStyle(
                          fontSize: 14,
                          color: Color(0xFF6B7280),
                        ),
                      ),

                      GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  RegisterPage(),
                            ),
                          );
                        },

                        child: const Text(
                          'Create account',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight:
                            FontWeight.w700,
                            color:
                            Color(0xFF2563EB),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 18),

                  // ==================================================
                  // SECURITY MESSAGE
                  // ==================================================

                  Row(
                    mainAxisAlignment:
                    MainAxisAlignment.center,

                    children: [
                      Icon(
                        Icons.verified_user_outlined,
                        size: 14,
                        color: Colors.grey.shade500,
                      ),

                      const SizedBox(width: 6),

                      Text(
                        'Your login is securely protected',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: Colors.grey.shade500,
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