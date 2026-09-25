import 'package:flutter/material.dart';
import '../widgets/app_chrome.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  static const String developerName = 'Nelson Grateron';
  static const String email = 'Nelson_the_master@hotmail.com';
  static const String phone = '0424-591-2742';

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: buildBrandAppBar(context, 'Acerca de'),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
          children: [
            const BrandBanner(
              title: 'Control de Guardias',
              subtitle: 'Organización · Disciplina · Servicio',
            ),
            const SizedBox(height: 14),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(22),
                      child: Image.asset(
                        'assets/brand/logo.png',
                        width: 116,
                        height: 116,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Control de Guardias',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: kBrandNavy,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Gestión de recorridos, descansos y disponibilidad semanal.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.black54),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            _info(Icons.person, 'Desarrollador', developerName),
            _info(Icons.email, 'Correo Electrónico', email),
            _info(Icons.phone, 'Teléfono', phone),
            const SizedBox(height: 8),
            const Center(
              child: Text(
                'La información de esta pantalla no es editable.',
                style: TextStyle(
                  color: Colors.grey,
                  fontStyle: FontStyle.italic,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      );

  Widget _info(IconData icon, String title, String value) => Card(
        child: ListTile(
          leading: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF2FC),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: kBrandNavy),
          ),
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          subtitle: Text(value),
        ),
      );
}
