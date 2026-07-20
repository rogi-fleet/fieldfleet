import 'package:flutter/material.dart';
import 'package:taskfleet_ops/widgets/common/form_popup_footer.dart';
import 'package:taskfleet_ops/widgets/common/form_popup_scaffold.dart';
import 'package:taskfleet_ops/models/vendor_contact.dart';
import 'package:taskfleet_ops/widgets/forms/stacked_field.dart';

Future<VendorContact?> showVendorContactFormDialog(
  BuildContext context, {
  VendorContact? existingContact,
}) {
  return showFormPopup<VendorContact>(
    context,
    icon: existingContact == null ? Icons.person_add : Icons.edit,
    title: existingContact == null ? 'Add Contact' : 'Edit Contact',
    width: 480,
    builder: (ctx, scrollController) => _VendorContactFormContent(
      existingContact: existingContact,
      scrollController: scrollController,
    ),
  );
}

class _VendorContactFormContent extends StatefulWidget {
  final VendorContact? existingContact;
  final ScrollController? scrollController;

  const _VendorContactFormContent({
    this.existingContact,
    this.scrollController,
  });

  @override
  State<_VendorContactFormContent> createState() =>
      _VendorContactFormContentState();
}

class _VendorContactFormContentState extends State<_VendorContactFormContent> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _titleController;
  late TextEditingController _phoneController;
  late TextEditingController _mobilePhoneController;
  late TextEditingController _emailController;

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
                  StackedField(
                    label: 'Title / Role',
                    child: TextFormField(
                      controller: _titleController,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.badge),
                        hintText: 'e.g., Sales Rep, Account Manager',
                      ),
                      textCapitalization: TextCapitalization.words,
                    ),
                  ),
                  const SizedBox(height: 16),
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
                  StackedField(
                    label: 'Office Phone',
                    child: TextFormField(
                      controller: _phoneController,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.phone),
                      ),
                      keyboardType: TextInputType.phone,
                    ),
                  ),
                  const SizedBox(height: 16),
                  StackedField(
                    label: 'Mobile Phone',
                    child: TextFormField(
                      controller: _mobilePhoneController,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.phone_android),
                      ),
                      keyboardType: TextInputType.phone,
                    ),
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
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final existing = widget.existingContact;
    Navigator.of(context).pop(
      VendorContact(
        name: _nameController.text.trim(),
        title: _titleController.text.trim().isEmpty
            ? null
            : _titleController.text.trim(),
        email: _emailController.text.trim().isEmpty
            ? null
            : _emailController.text.trim(),
        phone: _phoneController.text.trim().isEmpty
            ? null
            : _phoneController.text.trim(),
        mobilePhone: _mobilePhoneController.text.trim().isEmpty
            ? null
            : _mobilePhoneController.text.trim(),
        isPrimary: existing?.isPrimary ?? false,
        isActive: existing?.isActive ?? true,
        notes: existing?.notes,
      ),
    );
  }
}
