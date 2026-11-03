# قرار وتدقيق SQLCipher — الخطوة 6

**التاريخ:** 2026-11-03  
**الفرع:** `feat/sqlcipher-decision-a`  
**القرار المعتمد:** A — الإبقاء على `sqflite_sqlcipher` 3.4.1 مع تثبيت الإصدار وبصمة الحزمة، وإضافة اختبار عقد واختبار Android فعلي قبل أي ترحيل.

## 1. نطاق القرار

هذا المستند يغطي:

- إثبات أن التخزين المحلي يستخدم SQLCipher فعليًا، لا SQLite عاديًا.
- تدقيق مصدر الحزمة وسلسلة الاعتماديات.
- عزل واجهة فتح قاعدة البيانات دون إعادة كتابة `OfflineStore`.
- اختبارات عقد قابلة لإعادة الاستخدام عند الترحيل.
- اختبار تشفير فعلي على Android Emulator، بما فيه المفتاح الخاطئ والاستمرارية بعد إعادة الفتح.
- توثيق المخاطر والقيود وما هو مؤجل.

خارج النطاق:

- iOS/Keychain: مؤجل لأن هدف v1 الحالي هو Android، ولا يوجد دليل تشغيل iOS.
- جهاز Android فيزيائي أو StrongBox: غير مثبت في هذه الخطوة.
- تدقيق أمني مستقل للحزمة أو لمكتبة SQLCipher نفسها.
- ترحيل إلى البديل B.

## 2. هوية الحزمة والمصدر

| العنصر | القيمة |
|---|---|
| الحزمة | `sqflite_sqlcipher` |
| الإصدار المثبت | `3.4.1` |
| تاريخ النشر | 2026-08-04 |
| الناشر على pub.dev | غير موثق (`publisherId: null`) |
| المستودع | https://github.com/davidmartos96/sqflite_sqlcipher |
| وسم المصدر | `v3.4.1` |
| Commit المصدر | `e186c7f5c6b1c792e12c0a3838a1da10f4e5059e` |
| SHA-256 لأرشيف pub.dev | `50d05fe0495ed96a85503d9850a49c0936502f44fdba96f403c97e4c9c7043e7` |
| الترخيص | MIT (Tekartik) |

### مقارنة الأرشيف بالمصدر

- تم تنزيل أرشيف `3.4.1` من pub.dev والتحقق من SHA-256 أعلاه.
- تم استنساخ وسم `v3.4.1` من المستودع.
- الملفات المشتركة: 165 ملفًا.
- الاختلافات الجوهرية: 0.
- الأرشيف يحتوي `mise.toml` إضافيًا.
- المصدر يحتوي ملفات ignore/`.gitkeep` إضافية غير مؤثرة.
- لا يوجد كود شبكي أو إرسال بيانات في الحزمة؛ هي غلاف Dart/Android حول SQLCipher.

### لماذا لا يوجد Fork الآن

- لا توجد فائدة أمنية أو تشغيلية مثبتة من Fork حاليًا.
- المقارنة لم تكشف تعديلًا خفيًا في الأرشيف المنشور.
- أي Fork سينشئ عبء صيانة وتحديث أمني دون دليل على حاجة.
- يُعاد النظر إذا توقف المصدر، أو ظهرت CVE، أو احتاج المشروع تعديلًا غير قابل للضبط من التطبيق.

## 3. سلسلة الاعتماديات المثبتة

### Dart / Flutter

| الحزمة | الإصدار | الناشر | ملاحظة |
|---|---|---|---|
| `sqflite_sqlcipher` | 3.4.1 | غير موثق | مباشرة |
| `sqflite_common` | 2.5.6+1 | `tekartik.com` | مباشرة |
| `flutter_secure_storage` | 11.2.0 | `steenbakker.dev` | مباشرة |
| `flutter_secure_storage_darwin` | 0.4.3 | `steenbakker.dev` | transitive |
| `flutter_secure_storage_linux` | 3.0.3 | `steenbakker.dev` | transitive |
| `flutter_secure_storage_web` | 2.1.1 | `steenbakker.dev` | transitive |
| `flutter_secure_storage_windows` | 4.2.2 | `steenbakker.dev` | transitive |
| `flutter_secure_storage_platform_interface` | 2.1.1 | `steenbakker.dev` | transitive |
| `path_provider` | 2.1.6 | `flutter.dev` | transitive |
| `sqflite_common_ffi` | 2.3.7+1 | `tekartik.com` | dev فقط للاختبارات |
| `sqlite3` | 2.9.4 | `simonbinder.eu` | transitive عبر FFI، ليس محرك الإنتاج على Android |
| `integration_test` | SDK | `flutter.dev` | dev فقط |

تمت إضافة `mobile/pubspec.lock` و`mobile/example/pubspec.lock` لتثبيت الإصدارات وبصمات أرشيف pub.dev. بصمة `sqflite_sqlcipher` في القفلين هي نفس SHA-256 أعلاه.

### Android native

تثبت الحزمة داخل Gradle:

| العنصر | الإصدار | SHA-256 | المصدر |
|---|---|---|---|
| `net.zetetic:sqlcipher-android` | 4.10.0 (`@aar`) | `cc60b1a40d023bec06a1e56740db7172d2516668570140cd9de00ca90f84cd9f` | https://repo1.maven.org/maven2/net/zetetic/sqlcipher-android/4.10.0/sqlcipher-android-4.10.0.aar |
| `androidx.sqlite:sqlite` | 2.5.2 | `27aa89ed70281b9e663d5587a0f2f5ca876a9342f3b44d17b565fd0b5312ce5e` | https://dl.google.com/dl/android/maven2/androidx/sqlite/sqlite/2.5.2/sqlite-2.5.2.aar |

هذه النسخة هي التي تُحمّل فعليًا داخل تطبيق Android. `sqlite3` المذكور في Dart لا يُستخدم كمحرك الإنتاج على Android.

## 4. سلسلة حماية المفتاح

- مفتاح قاعدة البيانات يُولّد عشوائيًا بـ `Random.secure()`، 32 بايت، ويُرمّز Base64URL.
- يُخزّن في `flutter_secure_storage` تحت اسم ثابت: `shared_ledger_sqlcipher_key_v1`.
- على Android، الإصدار 11.2.0 يستخدم افتراضيًا:
  - مفتاح RSA في `AndroidKeyStore` بخيار OAEP/SHA-256/MGF1 لتغليف مفتاح التطبيق.
  - تشفير التخزين بـ AES-GCM.
- هذا يثبت أن المفتاح لا يُخزّن كنص صريح في ملفات التطبيق. لا يثبت أن كل جهاز يستخدم TEE أو StrongBox؛ ذلك يعتمد على الجهاز وإعدادات النظام.
- لا يوجد fallback إلى SQLite غير مشفر إذا فشل المفتاح أو التخزين الآمن.

**قيد مهم:** فقدان مفتاح التخزين الآمن (مسح بيانات التطبيق، تغيير توقيع التثبيت، إعادة تثبيت دون نسخ احتياطي آمن) يعني فقدان القدرة على فتح القاعدة. لا يوجد مفتاح استرداد في v1.

## 5. التعديلات البرمجية

### عزل واجهة فتح القاعدة

- أضيف في `mobile/lib/src/offline_store.dart`:
  - `offlineStoreDatabaseKeyName` كاسم عام قابل للاختبار.
  - `OfflineStoreDatabaseOpener` كـ typedef لعامل فتح القاعدة.
  - `databaseOpener` اختياري في `openEncrypted`.
  - `_openSqlCipherDatabase` كتنفيذ الإنتاج الافتراضي.
- لم يُعاد كتابة منطق `OfflineStore` أو مخططه.
- الإنتاج يستخدم SQLCipher افتراضيًا حتى عند عدم تمرير عامل فتح.
- `openForTesting` بقي كما هو للاختبارات السريعة غير المشفرة، ولا يُستخدم في الإنتاج.

### اختبارات العقد

- `mobile/test/offline_store_contract.dart` يحتوي سلوك `OfflineStore` القابل لإعادة الاستخدام.
- `mobile/test/offline_store_test.dart` يشغّل العقد على `sqflite_common_ffi` للسرعة.
- نفس العقد يمكن تشغيله لاحقًا على محرك بديل عند اختبار الترحيل إلى B.

### اختبار Android الفعلي

- `mobile/example` مضيف Android مخصص للاختبار التكاملي.
- `mobile/example/integration_test/encrypted_store_test.dart` يختبر:
  1. عدم وجود marker نصي في ملفات `.db` و`-wal` و`-shm` و`-journal`.
  2. أن رأس ملف القاعدة ليس رأس SQLite الصريح `SQLite format 3`.
  3. فشل المفتاح الخاطئ صراحة دون حذف أو إعادة كتابة ملفات القاعدة.
  4. نجاح إعادة الفتح بالمفتاح الصحيح واستعادة البيانات بعد محاولة المفتاح الخاطئ.
  5. رفض مفتاح قصير قبل إنشاء القاعدة.
  6. قراءة/كتابة المفتاح عبر `flutter_secure_storage` على Android.

## 6. مصفوفة التحقق

| البند | الأداة | الحالة |
|---|---|---|
| تثبيت إصدار الحزمة وبصمة الأرشيف | `pubspec.yaml` + `pubspec.lock` | منفَّذ |
| مقارنة الأرشيف بالمصدر | تنزيل + استنساخ + مقارنة | منفَّذ |
| تثبيت سلسلة Android native | Gradle + فحص AAR | منفَّذ |
| اختبارات العقد على FFI | `flutter test` | ناجح محليًا |
| تحليل Dart للحزمة | `flutter analyze` | ناجح محليًا |
| تحليل مضيف Android | `flutter analyze` في `mobile/example` | ناجح محليًا |
| بناء APK | `flutter build apk --debug` عبر CI / Android runner | ناجح ضمن اختبار Android؛ المحاولة المحلية تعطلت بنفاد مساحة القرص فقط |
| اختبار SQLCipher على Android Emulator | GitHub Actions | **ناجح — 3 اختبارات، Run `41549859547`** |
| Keystore على جهاز فيزيائي/StrongBox | اختبار ميداني | مؤجل |
| iOS Keychain | لا يوجد هدف iOS في v1 | مؤجل صراحة |


## 6.1 نتيجة CI الفعلية

- PR #46: https://github.com/overurdream-collab/test4/pull/46
- Merge SHA: `a5421340c63b6217ade526af7eae98755e189e3b`.
- Commit الكود المختبَر: `e8ea5123de955583ae6696d7b025dc433d05089d`، وآخر head قبل الدمج: `396ea847fa32216426d5b4f035af7345567d81d1`.
- Android SQLCipher checks Run `41549859547`: **success** على آخر head قبل الدمج.
  - Job: https://github.com/overurdream-collab/test4/actions/runs/41549859547/job/125634476073
  - النتيجة في السجل: `3 tests passed`.
  - التشغيل السابق `41548693837` كان ناجحًا أيضًا على commit الكود `e8ea512`.
  - الاختبارات: التشفير وإعادة الفتح، المفتاح الخاطئ وعدم مسح البيانات، رفض المفتاح القصير.
- Flutter CI Run `41549859536`: success على آخر head قبل الدمج.
  https://github.com/overurdream-collab/test4/actions/runs/41549859536
- Mobile offline store checks Run `41549859538`: success.
  https://github.com/overurdream-collab/test4/actions/runs/41549859538
- Ledger PostgreSQL tests Run `41549859540`: success.
  https://github.com/overurdream-collab/test4/actions/runs/41549859540
- بعد الدمج على main: Flutter CI Run `41550635114` success، وLedger PostgreSQL Run `41550635120` success.
  https://github.com/overurdream-collab/test4/actions/runs/41550635114
  https://github.com/overurdream-collab/test4/actions/runs/41550635120

### محاولة فاشلة جرى إصلاحها

- Run `41548178855` فشل في خطوة الاختبار، وليس في التشفير.
- السبب: `reactivecircus/android-emulator-runner` ينفذ كل سطر من `script` في shell منفصل، لذلك لم يستمر `cd mobile/example` إلى سطر `flutter test`.
- الإصلاح: تحويل الخطوتين إلى أمر واحد `cd mobile/example && flutter test ...` في commit `e8ea512`.
- النتيجة: Run `41548693837` ناجح، 3 اختبارات passed، وتكرر النجاح على آخر head في Run `41549859547`.
- لم يُخفَ الفشل ولم يُعدل الاختبار ليمر.

## 7. مطابقة الضوابط التسعة للقرار A

| الضابط | التنفيذ |
|---|---|
| 1. الاحتفاظ بالإصدار وتثبيت البصمة | `sqflite_sqlcipher: 3.4.1` + SHA-256 في القفلين |
| 2. تدقيق المصدر والاعتماديات | مقارنة 165 ملفًا، 0 اختلافات؛ توثيق AAR وAndroidX |
| 3. لا Fork بلا فائدة واضحة | قرار موثق بعدم الحاجة الحالية |
| 4. عزل واجهة التخزين بأقل تعديل | typedef + عامل فتح اختياري دون إعادة كتابة |
| 5. Contract Tests قابلة لإعادة الاستخدام | `offline_store_contract.dart` |
| 6. إثبات التشفير والمفتاح الخاطئ والسلامة | اختبار Android تكاملي |
| 7. Keystore/Keychain حسب المنصة | Android Keystore عبر `flutter_secure_storage`؛ iOS مؤجل |
| 8. Android Emulator CI | `.github/workflows/android-sqlcipher.yml` |
| 9. توثيق القرار والمخاطر والنتائج | هذا المستند + الحالة + سجل القرارات + Handoff |

## 8. المخاطر المتبقية

| الخطر | الأثر | التخفيف الحالي | المتبقي |
|---|---|---|---|
| ناشر الحزمة غير موثق | ثقة أقل في سلسلة التوريد | مقارنة الأرشيف بالمصدر + تثبيت البصمة | مراجعة دورية عند كل تحديث |
| صيانة فردية للمستودع | تأخر إصلاحات أمنية | نسخة مثبتة + مراقبة CVE | خطة Fork عند الحاجة |
| SQLCipher AAR ثنائي غير مبني من المصدر محليًا | ثقة محدودة في الملف الثنائي | تثبيت SHA-256 من Maven | تدقيق ثنائي مستقل مؤجل |
| الاختبار على Emulator فقط | لا يغطي أجهزة فعلية | اختبار CI إلزامي | اختبار جهاز فيزيائي قبل الإطلاق |
| فقدان المفتاح = فقدان البيانات | فقدان محلي لا رجعة فيه | توثيق صريح | سياسة نسخ/استرداد قبل الإنتاج |
| لا اختبار iOS | فجوة عند توسعة المنصات | iOS خارج v1 | بوابة منفصلة عند إضافته |
| اقتران `sqflite_common` بإصدار الحزمة | ترحيل B يتطلب تغييرات | عقد اختبار معزول | إبقاء الواجهة ضيقة |

## 9. معايير الخروج من الخطوة 6

تم استيفاء المعايير التالية:

1. نجاح `Android SQLCipher checks` مع Run URL `41549859547` و`3 tests passed`.
2. نجاح `Flutter CI` Run `41549859536` و`Mobile offline store checks` Run `41549859538`.
3. نجاح اختبارات العقد والتحليل محليًا وفي CI.
4. دمج PR #46 بـ Merge SHA `a5421340c63b6217ade526af7eae98755e189e3b`.
5. تحديث الحالة وWorklog وHandoff بالـ SHA وRun URLs.
6. الإفصاح عن المحاولة الفاشلة `41548178855` وإصلاحها دون تعطيل الاختبار.

## 10. البديل B — ملخص الترحيل

`sqlite3` 3.8.0 من `simonbinder.eu` يدعم SQLCipher عبر hooks `source: sqlcipher`، لكنه يتطلب إعادة كتابة طبقة التخزين وربما تغيير نمط الفتح والاستعلامات. `sqlcipher_flutter_libs` أصبح EOL. لا يُنتقل إلى B إلا إذا:

- فشل إثبات SQLCipher الحالي على Android، أو
- ظهرت مشكلة صيانة/أمان في الحزمة الحالية، أو
- أصبحت متطلبات المنصات (مثل iOS) غير قابلة للتحقيق مع A.

عندها يعاد استخدام Contract Tests نفسها للتحقق من عدم تغير السلوك.
