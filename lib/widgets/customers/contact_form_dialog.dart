import 'package:flutter/material.dart';
import 'package:taskfleet_ops/widgets/common/form_popup_footer.dart';
import 'package:taskfleet_ops/widgets/common/form_popup_scaffold.dart';
import '../../models/customer_contact.dart';

import 'package:taskfleet_ops/widgets/forms/stacked_field.dart';

Future<CustomerContact?> showContactFormDialog(
  BuildContext context, {
  CustomerContact? existingContact,
  bool canSetPrimary = true,
  bool defaultPrimary = false,
}) {
  return showFormPopup<CustomerContact>(
    context,
    icon: existingContact == null ? Icons.person_add : Icons.edit,
    title: existingContact == null ? 'Add Contact' : 'Edit Contact',
    width: 480,
    builder: (ctx, scrollController) => _ContactFormContent(
      existingContact: existingContact,
      canSetPrimary: canSetPrimary,
      defaultPrimary: defaultPrimary,
      scrollController: scrollController,
    ),
  );
}

class _ContactFormContent extends StatefulWidget {
  final CustomerContact? existingContact;
  final bool canSetPrimary;
  final bool defaultPrimary;
  final ScrollController? scrollController;

  const _ContactFormContent({
    this.existingContact,
    this.canSetPrimary = true,
    this.defaultPrimary = false,
    this.scrollController,
  });

  @override
  State<_ContactFormContent> createState() => _ContactFormContentState();
}

class _ContactFormContentState extends State<_ContactFormContent> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _titleController;
  late TextEditingController _phoneController;
  late TextEditingController _mobilePhoneController;
  late TextEditingController _emailController;
  late bool _isPrimary;

  @override
  void initState() {
    super.initState();
    final contact = widget.existingContact;
    _nameController = TextEditingController(text: contact?.name ?? '');
    _titleController = TextEditingController(text: contact?.title ?? '');
    _phoneController = TextEditingController(text: contact?.phone ?? '');
    _mobilePhoneController = TextEditingController(
      text: contact?.mobilePhone ?? '',
    );
    _emailController = TextEditingController(text: contact?.email ?? '');
    // Set isPrimary to true if this is the first contact, otherwise use existing value or false
    _isPrimary = contact?.isPrimary ?? widget.defaultPrimary;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _titleController.dispose();
    _phoneController.dispose();
    _mobilePhoneController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              controller: widget.scrollController,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Name field
                  StackedField(
                    label: 'Name *',
                    child: TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.person),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Name is required';
                        }
                        return null;
                      },
                      textCapitalization: TextCapitalization.words,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Title field
                  StackedField(
                    label: 'Title / Role',
                    child: TextFormField(
                      controller: _titleController,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.badge),
                        hintText: 'e.g., Owner, Project Manager',
                      ),
                      textCapitalization: TextCapitalization.words,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Phone field
                  StackedField(
                    label: 'Phone',
                    child: TextFormField(
                      controller: _phoneController,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.phone),
                      ),
                      keyboardType: TextInputType.phone,
                      validator: (value) {
                        if (value != null && value.isNotEmpty) {
                          final phoneRegex = RegExp(r'^[0-9\s\-\(\)\+]+$');
                          if (!phoneRegex.hasMatch(value)) {
                            return 'Invalid phone format';
                          }
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(height: 16),

                  StackedField(
                    label: 'Cell Phone',
                    child: TextFormField(
                      controller: _mobilePhoneController,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.phone_android),
                      ),
                      keyboardType: TextInputType.phone,
                      validator: (value) {
                        if (value != null && value.isNotEmpty) {
                          final phoneRegex = RegExp(r'^[0-9\s\-\(\)\+]+$');
                          if (!phoneRegex.hasMatch(value)) {
                            return 'Invalid phone format';
                          }
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Email field
                  StackedField(
                    label: 'Email',
                    child: TextFormField(
                      controller: _emailController,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.email),
                      ),
                      keyboardType: TextInputType.emailAddress,
                      validator: (value) {
                        if (value != null && value.isNotEmpty) {
                          final emailRegex = RegExp(
                            r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
                          );
                          if (!emailRegex.hasMatch(value)) {
                            return 'Invalid email format';
                          }
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Primary checkbox
                  if (widget.canSetPrimary)
                    CheckboxListTile(
                      value: _isPrimary,
                      onChanged: (value) {
                        setState(() {
                          _isPrimary = value ?? false;
                        });
                      },
                      title: const Text('Set as Primary Contact'),
                      subtitle: const Text(
                        'This will be the default contact for this customer',
                      ),
                      contentPadding: EdgeInsets.zero,
                    ),
                ],
              ),
            ),
          ),
        ),
        FormPopupFooter(
          onSubmit: _saveContact,
          submitLabel: 'Save',
        ),
      ],
    );
  }

  void _saveContact() {
    if (_formKey.currentState!.validate()) {
      final contact = CustomerContact(
        name: _nameController.text.trim(),
        title: _titleController.text.trim().isEmpty
            ? null
            : _titleController.text.trim(),
        phone: _phoneController.text.trim().isEmpty
            ? null
            : _phoneController.text.trim(),
        mobilePhone: _mobilePhoneController.text.trim().isEmpty
            ? null
            : _mobilePhoneController.text.trim(),
        email: _emailController.text.trim().isEmpty
            ? null
            : _emailController.text.trim(),
        isPrimary: _isPrimary,
        isActive: true,
      );

      Navigator.of(context).pop(contact);
    }
  }
}
