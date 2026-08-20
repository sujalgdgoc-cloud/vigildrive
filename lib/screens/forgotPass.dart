import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() =>
      _ForgotPasswordPageState();
}

class _ForgotPasswordPageState
    extends State<ForgotPasswordPage> {
  final TextEditingController _emailController =
  TextEditingController();

  final GlobalKey<FormState> _formKey =
  GlobalKey<FormState>();

  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  // ============================================================
  // SEND PASSWORD RESET EMAIL
  // ============================================================

  Future<void> _sendResetLink() async {
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

      await FirebaseAuth.instance.sendPasswordResetEmail(
        email: email,
      );

      if (!mounted) return;

      _showMessage(
        'Password reset link sent to your email.',
        isError: false,
      );

      // Go back to login after successfully sending
      // the reset email.
      await Future.delayed(
        const Duration(milliseconds: 900),
      );

      if (!mounted) return;

      Navigator.pop(context);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;

      String message;

      switch (e.code) {
        case 'invalid-email':
          message =
          'Please enter a valid email address.';
          break;

        case 'user-not-found':
          message =
          'No account was found with this email.';
          break;

        case 'too-many-requests':
          message =
          'Too many requests. Please try again later.';
          break;

        case 'network-request-failed':
          message =
          'Network error. Check your internet connection.';
          break;

        default:
          message =
              e.message ??
                  'Unable to send the reset link.';
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
            borderRadius:
            BorderRadius.circular(12),
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

  InputDecoration _emailDecoration() {
    return InputDecoration(
      hintText: 'Enter your email address',

      prefixIcon: const Icon(
        Icons.email_outlined,
        size: 21,
        color: Color(0xFF9AA2B1),
      ),

      filled: true,

      fillColor: Colors.white,

      contentPadding:
      const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 17,
      ),

      hintStyle: const TextStyle(
        color: Color(0xFF9AA2B1),
        fontSize: 15,
      ),

      border: OutlineInputBorder(
        borderRadius:
        BorderRadius.circular(12),

        borderSide: const BorderSide(
          color: Color(0xFFD9DEE8),
        ),
      ),

      enabledBorder: OutlineInputBorder(
        borderRadius:
        BorderRadius.circular(12),

        borderSide: const BorderSide(
          color: Color(0xFFD9DEE8),
        ),
      ),

      focusedBorder: OutlineInputBorder(
        borderRadius:
        BorderRadius.circular(12),

        borderSide: const BorderSide(
          color: Color(0xFF2563EB),
          width: 1.7,
        ),
      ),

      errorBorder: OutlineInputBorder(
        borderRadius:
        BorderRadius.circular(12),

        borderSide: const BorderSide(
          color: Color(0xFFDC2626),
        ),
      ),

      focusedErrorBorder:
      OutlineInputBorder(
        borderRadius:
        BorderRadius.circular(12),

        borderSide: const BorderSide(
          color: Color(0xFFDC2626),
          width: 1.5,
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
      backgroundColor:
      const Color(0xFFF8F7F4),

      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding:
            const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 28,
            ),

            child: ConstrainedBox(
              constraints:
              const BoxConstraints(
                maxWidth: 440,
              ),

              child: Column(
                children: [
                  // ==================================================
                  // BACK TO LOGIN
                  // ==================================================

                  Align(
                    alignment:
                    Alignment.centerLeft,

                    child: TextButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                      },

                      style: TextButton.styleFrom(
                        foregroundColor:
                        const Color(0xFF526173),

                        padding:
                        const EdgeInsets.symmetric(
                          horizontal: 0,
                          vertical: 8,
                        ),
                      ),

                      icon: const Icon(
                        Icons.arrow_back_rounded,
                        size: 19,
                      ),

                      label: const Text(
                        'Back to Login',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight:
                          FontWeight.w700,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 36),

                  // ==================================================
                  // RESET ICON
                  // ==================================================

                  Container(
                    width: 56,
                    height: 56,

                    decoration: BoxDecoration(
                      shape: BoxShape.circle,

                      color: Colors.white,

                      border: Border.all(
                        color: const Color(
                          0xFFDDE5F0,
                        ),
                      ),
                    ),

                    child: const Center(
                      child: Icon(
                        Icons.lock_reset_rounded,
                        size: 28,
                        color: Color(0xFF2563EB),
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // ==================================================
                  // TITLE
                  // ==================================================

                  const Text(
                    'Forgot Password?',
                    textAlign: TextAlign.center,

                    style: TextStyle(
                      fontSize: 26,
                      fontWeight:
                      FontWeight.w800,
                      letterSpacing: -0.5,
                      color: Color(0xFF111827),
                    ),
                  ),

                  const SizedBox(height: 9),

                  const Text(
                    'Enter your email address and we\'ll send you a password reset link.',
                    textAlign: TextAlign.center,

                    style: TextStyle(
                      fontSize: 14.5,
                      height: 1.45,
                      color: Color(0xFF6B7280),
                      fontWeight:
                      FontWeight.w500,
                    ),
                  ),

                  const SizedBox(height: 30),

                  // ==================================================
                  // FORM
                  // ==================================================

                  Form(
                    key: _formKey,

                    child: Column(
                      crossAxisAlignment:
                      CrossAxisAlignment.start,

                      children: [
                        const Text(
                          'EMAIL ADDRESS',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight:
                            FontWeight.w800,
                            letterSpacing: 0.2,
                            color:
                            Color(0xFF4B5563),
                          ),
                        ),

                        const SizedBox(height: 8),

                        TextFormField(
                          controller:
                          _emailController,

                          keyboardType:
                          TextInputType.emailAddress,

                          textInputAction:
                          TextInputAction.done,

                          autocorrect: false,

                          onFieldSubmitted: (_) {
                            if (!_isLoading) {
                              _sendResetLink();
                            }
                          },

                          decoration:
                          _emailDecoration(),

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

                        const SizedBox(height: 24),

                        // ==================================================
                        // SEND RESET LINK BUTTON
                        // ==================================================

                        SizedBox(
                          width: double.infinity,
                          height: 54,

                          child: ElevatedButton(
                            onPressed:
                            _isLoading
                                ? null
                                : _sendResetLink,

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
                                  : const Row(
                                key: ValueKey(
                                  'send',
                                ),

                                mainAxisAlignment:
                                MainAxisAlignment
                                    .center,

                                children: [
                                  Text(
                                    'SEND RESET LINK',

                                    style:
                                    TextStyle(
                                      fontSize: 14,
                                      fontWeight:
                                      FontWeight
                                          .w800,
                                      letterSpacing:
                                      0.3,
                                    ),
                                  ),

                                  SizedBox(
                                    width: 8,
                                  ),

                                  Icon(
                                    Icons
                                        .arrow_forward_rounded,
                                    size: 19,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 43),

                  // ==================================================
                  // HELP
                  // ==================================================

                  Row(
                    mainAxisAlignment:
                    MainAxisAlignment.center,

                    children: [
                      const Text(
                        'Need help? ',

                        style: TextStyle(
                          fontSize: 14,
                          color:
                          Color(0xFF6B7280),
                        ),
                      ),

                      GestureDetector(
                        onTap: () {
                          // Add your support/dispatch
                          // contact action here.
                        },

                        child: const Text(
                          'Contact Dispatch',

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

                  const SizedBox(height: 20),

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
                        'Your password reset is secure',

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