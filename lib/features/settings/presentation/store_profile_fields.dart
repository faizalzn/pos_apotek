import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../data/settings_repository.dart';

/// Pengendali isian profil apotek, dipakai di wizard dan di Pengaturan.
class StoreProfileControllers {
  StoreProfileControllers([StoreProfile? initial])
      : name = TextEditingController(text: initial?.name),
        address = TextEditingController(text: initial?.address),
        phone = TextEditingController(text: initial?.phone),
        footer = TextEditingController(
          text: initial?.receiptFooter ?? StoreProfile.defaultReceiptFooter,
        );

  final TextEditingController name;
  final TextEditingController address;
  final TextEditingController phone;
  final TextEditingController footer;

  void load(StoreProfile p) {
    name.text = p.name;
    address.text = p.address;
    phone.text = p.phone;
    footer.text = p.receiptFooter;
  }

  StoreProfile toProfile() => StoreProfile(
        name: name.text,
        address: address.text,
        phone: phone.text,
        receiptFooter: footer.text,
      );

  void dispose() {
    name.dispose();
    address.dispose();
    phone.dispose();
    footer.dispose();
  }
}

/// Isian nama, alamat, telepon (dan catatan struk) apotek.
class StoreProfileFields extends StatelessWidget {
  const StoreProfileFields({
    super.key,
    required this.controllers,
    this.showReceiptFooter = false,
  });

  final StoreProfileControllers controllers;
  final bool showReceiptFooter;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          key: const Key('store-name'),
          controller: controllers.name,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            labelText: 'Nama apotek *',
            hintText: 'mis. Apotek Sehat Sentosa',
            prefixIcon: Icon(Icons.local_pharmacy_outlined),
          ),
          validator: (v) =>
              (v == null || v.trim().isEmpty) ? 'Nama apotek wajib diisi' : null,
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: controllers.address,
          textCapitalization: TextCapitalization.sentences,
          textInputAction: TextInputAction.next,
          minLines: 1,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Alamat',
            prefixIcon: Icon(Icons.place_outlined),
          ),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: controllers.phone,
          keyboardType: TextInputType.phone,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9+\- ]')),
          ],
          decoration: const InputDecoration(
            labelText: 'No. telepon / WhatsApp',
            prefixIcon: Icon(Icons.phone_outlined),
          ),
        ),
        if (showReceiptFooter) ...[
          const SizedBox(height: 16),
          TextFormField(
            controller: controllers.footer,
            minLines: 1,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Catatan di bawah struk',
              prefixIcon: Icon(Icons.receipt_long_outlined),
            ),
          ),
        ],
        const SizedBox(height: 8),
        Text(
          'Logo apotek bisa ditambahkan nanti di bagian pengaturan struk.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
