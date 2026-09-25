# Control de Guardias

Proyecto Flutter de Control de Guardias.

## Verificación automática

El repositorio contiene `Control_Guardia.zip` y el workflow de GitHub Actions extrae ese ZIP antes de verificarlo.

La verificación automática ejecuta, en este orden:

1. Comprueba que el ZIP exista y tenga `pubspec.yaml` y código Dart.
2. Instala Flutter 3.35.2.
3. Genera automáticamente la plataforma Android si el ZIP no la incluye.
4. Ejecuta `flutter pub get`.
5. Ejecuta `dart format --output=none --set-exit-if-changed lib test` para detectar errores de parsing en todos los archivos Dart.
6. Ejecuta `flutter analyze` sobre todo el proyecto.
7. Ejecuta todas las pruebas.
8. Solo si todo lo anterior pasa, construye el APK release.

El APK se publica como artefacto de la ejecución.
