# نظام حجز مركز الترفيه الطلابي · Campus Recreation Center Booking

© 2026 Services Squire LLC. جميع الحقوق محفوظة · All rights reserved.

تطبيق ويب ثنائي اللغة (عربي / إنجليزي) لحجز ساعات وألعاب مركز الترفيه الطلابي، يعمل على GitHub Pages ويحفظ بياناته في Supabase.

A bilingual (Arabic / English) booking app for a campus recreation center. It runs on GitHub Pages and stores its data in Supabase.

---

## المحتويات · Contents

| الملف · File | الوصف · Description |
|---|---|
| `index.html` | التطبيق كاملاً · The whole app |
| `config.js` | رابط Supabase ومفتاحه العام · Supabase URL and public key |
| `manifest.webmanifest`, `sw.js`, `icons/` | تثبيت التطبيق على الهاتف · Installable app (PWA) |
| `android/`, `.github/workflows/android.yml` | تطبيق أندرويد (APK) · Android app |
| `supabase/schema.sql` | الجداول وقواعد الحماية ودوال الحجز · Tables, security rules, booking functions |
| `supabase/functions/admin/index.ts` | دالة الخادم لحسابات الإدارة وكلمات المرور المؤقتة · Server function for staff accounts and temporary passwords |

---

## العربية: خطوات التشغيل

### ١. إنشاء مشروع Supabase
1. ادخل إلى [supabase.com](https://supabase.com) وأنشئ حساباً مجانياً، ثم **New project**.
2. اختر اسماً وكلمة مرور لقاعدة البيانات، واختر أقرب منطقة لكم.
   > بيانات الطلاب (الاسم والرقم الجامعي والهاتف) ستُحفظ في هذه المنطقة؛ تأكد من توافق ذلك مع سياسة حماية البيانات في جامعتكم.

### ٢. إنشاء قاعدة البيانات
1. من القائمة الجانبية: **SQL Editor** ثم **New query**.
2. انسخ محتوى الملف `supabase/schema.sql` كاملاً والصقه، ثم **Run**.

### ٣. إعداد تسجيل الدخول
1. **Authentication** ثم **Sign In / Providers** ثم **Email**.
2. تأكد أن **Enable Email provider** مفعّل.
3. **أوقف** خيار **Confirm email** ثم احفظ.
   > الطلاب يسجّلون برقمهم الجامعي، والتطبيق يحوّله داخلياً إلى عنوان بريد شكلي لا يستقبل رسائل؛ لذلك يجب إيقاف تأكيد البريد.

### ٤. نشر دالة الإدارة
1. **Edge Functions** ثم **Deploy a new function** ثم **Via Editor**.
2. سمِّ الدالة `admin` بالضبط.
3. احذف المحتوى الافتراضي، والصق محتوى `supabase/functions/admin/index.ts`، ثم **Deploy**.
4. من إعدادات الدالة أوقف **Verify JWT** (الدالة تتحقق من المستخدم بنفسها).

(أو عبر سطر الأوامر: `supabase functions deploy admin --no-verify-jwt`)

### ٥. ربط التطبيق
1. **Project Settings** ثم **API**.
2. انسخ **Project URL** و **anon public key**.
3. افتح `config.js` وضعهما مكان `YOUR-PROJECT` و `YOUR-ANON-KEY`.
   > المفتاح العام (anon) آمن للنشر؛ الحماية تتم عبر قواعد قاعدة البيانات. **لا تضع أبداً** مفتاح `service_role` في هذا الملف.

### ٦. النشر على GitHub Pages
1. أنشئ مستودعاً جديداً على GitHub وارفع جميع الملفات.
2. **Settings** ثم **Pages**، ثم في **Source** اختر **Deploy from a branch**، والفرع `main` والمجلد `/ (root)`، ثم **Save**.
3. بعد دقيقة يظهر رابط الموقع.

### ٧. أول تشغيل
1. افتح الموقع ثم تبويب **الإدارة**.
2. ستظهر شاشة **إنشاء أول مدير نظام**؛ أنشئ حسابك (تظهر مرة واحدة فقط).
3. من **الإعدادات**: عدّل اسم المركز وشعاره والأقسام والساعات، وأنشئ حسابات الموظفين.
4. شارك رابط الموقع مع الطلاب.

### الصلاحيات

| الحساب | ما يستطيعه |
|---|---|
| موظف استقبال | المسح، الاستقبال وتسجيل الحضور، مراسلة الطلاب، التقارير، الإحصائيات، التنبيهات |
| مدير النظام | كل ما سبق + الإعدادات (الأقسام، الساعات، الإغلاق، الإلغاء التلقائي) وحسابات الموظفين والطلاب |
| المطوّر | كل صلاحيات المدير + تغيير اسم المركز والشعار + إرسال تنبيهات للمشرفين والمدير |
| متابعة فقط | الإحصائيات وحركة الحجز (عرض فقط) ومراسلة المشرفين والمدير، دون أي تعديل |

يُنشئ مدير النظام أول حساب مطوّر مرة واحدة من «الإعدادات ← حسابات الإدارة»، وبعدها لا يُنشئ حسابات المطوّر أو يعدّلها إلا المطوّر. الصلاحيات مفروضة في قاعدة البيانات نفسها وليست مجرد إخفاء في الواجهة.

### الإلغاء التلقائي لعدم الحضور

تعمل مهمة على الخادم كل دقيقة (pg_cron). إذا لم يُسجَّل حضور الطالب بعد بداية الساعة بـ 10 دقائق (قابلة للتعديل) يُلغى الحجز ويتحرر المقعد، ويصل للطالب إشعار وللمشرفين تنبيه في تبويب 🔔 التنبيهات. عند تكرار عدم الحضور (مرتان خلال 30 يوماً افتراضياً) يصدر إنذار تلقائي ويُنبَّه المشرف. تُضبط القيم أو يُوقف ذلك من الإعدادات. إذا لم يُفعَّل pg_cron عند التثبيت شغّل `supabase/migrations/008_auto_no_show_schedule.sql`.

### تطبيق ويندوز (Windows 10/11)

رابط التحميل الثابت: https://github.com/kss9393-OM/rec-center-booking/releases/download/windows-app/RecCenter-Setup.exe

شغّل `RecCenter-Setup.exe` واختر مكان التثبيت؛ يُنشأ اختصار «مركز الترفيه الطلابي» على سطح المكتب وقائمة ابدأ. الملف غير موقّع رقمياً، لذا قد يظهر تحذير «Windows protected your PC»: اضغط «More info» ثم «Run anyway». التطبيق يفتح النظام المباشر، فكل تحديث للموقع يظهر فيه تلقائياً. أجهزة المسح بمنفذ USB (تعمل كلوحة مفاتيح) تعمل في تبويب المسح مباشرة. يُبنى المثبّت تلقائياً عبر GitHub Actions عند تغيير مجلد `windows/`.

### تطبيق أندرويد (APK)
يُبنى التطبيق تلقائياً على GitHub مع كل تحديث لمجلد `android/`، ويُنشر في صفحة **Releases** باسم **Android app**.
- **رابط التنزيل الدائم:** https://github.com/kss9393-OM/rec-center-booking/releases/latest/download/rec-center.apk
- **التثبيت:** افتح الرابط على الجهاز ← نزّل الملف ← افتحه ← اسمح بالتثبيت من هذا المصدر عند السؤال ← **تثبيت**.
- **على أجهزة Honeywell (مثل EDA52):** يقرأ التطبيق الماسح مباشرة دون أي إعداد في الجهاز. على الأجهزة الأخرى يعمل المسح بالكاميرا.
- **التحديث:** نزّل الملف من نفس الرابط وثبّته فوق النسخة الحالية.
- **التوقيع:** ملف المفتاح `android/keystore/crc-release.jks` مشفّر بكلمة مرور محفوظة فقط في **Settings ← Secrets and variables ← Actions** باسم `ANDROID_KEYSTORE_PASSWORD`. احتفظ بنسخة من كلمة المرور في مكان آمن؛ بدونها لا يمكن إصدار تحديثات تُثبَّت فوق التطبيق.

### ماسح التذاكر (Honeywell EDA52 وأجهزة المسح المشابهة)
**إعداد الجهاز مرة واحدة:** الإعدادات ← **Honeywell Settings** ← **Scanning** ← **Internal Scanner** ← **Default Profile** ← **Data Processing Settings**:
- **Wedge:** مفعّل.
- **Wedge Method:** ‏Keyboard (أو Standard).
- **Suffix:** ‏`\n` (إدخال Enter بعد كل مسح) — يُفضَّل، والتطبيق يعمل بدونه أيضاً.
- تأكد من تفعيل **QR Code** في **Symbology Settings** (مفعّل عادةً).

**الاستخدام:** افتح الموقع في Chrome على الجهاز ← ثبّته كتطبيق ← **الإدارة** ← سجّل الدخول ← تبويب **المسح**، ثم اضغط زر المسح الجانبي على تذكرة الطالب. يُسجَّل الدخول فوراً مع صوت واهتزاز ونتيجة ملوّنة (أخضر: تم، أصفر: يحتاج انتباه، أحمر: مرفوض).
إذا ظهر الرمز في الخانة دون أن يُرسَل: أضف Suffix ‏`\n`. إذا لم يظهر شيء: غيّر Wedge Method إلى Keyboard.

### تثبيت التطبيق على أندرويد
1. افتح رابط الموقع في **Chrome** على الهاتف.
2. اضغط زر **تثبيت التطبيق** في أعلى الصفحة، أو من قائمة Chrome (⋮) اختر **تثبيت التطبيق** / **إضافة إلى الشاشة الرئيسية**.
3. يظهر التطبيق بشعار الكلية على الشاشة الرئيسية ويفتح بملء الشاشة. أي تحديث على GitHub يصل إليه تلقائياً.

**على iPhone / iPad:** افتح الرابط في **Safari** ← اضغط **تثبيت التطبيق** أعلى الصفحة لعرض الخطوات، أو مباشرة: زر المشاركة ← **إضافة إلى الشاشة الرئيسية** ← **إضافة**. التقارير والتذاكر تُحفظ عبر قائمة المشاركة (الحفظ في الملفات، AirDrop، …).

---

## English: setup

### 1. Create a Supabase project
1. Sign up at [supabase.com](https://supabase.com) (free plan) and choose **New project**.
2. Pick a name, a database password and the region closest to you.
   > Student data (name, student ID, phone) is stored in that region; check it matches your university's data-protection policy.

### 2. Create the database
1. **SQL Editor** → **New query**.
2. Paste the whole of `supabase/schema.sql` and click **Run**.

### 3. Configure sign-in
1. **Authentication** → **Sign In / Providers** → **Email**.
2. Make sure **Enable Email provider** is on.
3. Turn **off** **Confirm email** and save.
   > Students sign in with their student ID, which the app turns into a placeholder address that never receives mail, so email confirmation must be off.

### 4. Deploy the admin function
1. **Edge Functions** → **Deploy a new function** → **Via Editor**.
2. Name it exactly `admin`.
3. Replace the template with the contents of `supabase/functions/admin/index.ts` and click **Deploy**.
4. In the function's settings, turn **Verify JWT** off (the function checks the caller itself).

(Or from the CLI: `supabase functions deploy admin --no-verify-jwt`)

### 5. Connect the app
1. **Project Settings** → **API**.
2. Copy the **Project URL** and the **anon public key**.
3. Put them in `config.js` in place of `YOUR-PROJECT` and `YOUR-ANON-KEY`.
   > The anon key is safe to publish; access is enforced by the database rules. **Never** put the `service_role` key in this file.

### 6. Publish on GitHub Pages
1. Create a GitHub repository and upload all files.
2. **Settings** → **Pages** → **Source: Deploy from a branch**, branch `main`, folder `/ (root)` → **Save**.
3. The site link appears after about a minute.

### 7. First run
1. Open the site and go to **Management**.
2. The **Create the first system admin** screen appears once; create your account.
3. In **Settings**, set the center name, logo, zones and hours, and create staff accounts.
4. Share the site link with students.

### Roles

| Account | Can do |
|---|---|
| Reception staff | Scanning, desk check-ins, student messages, reports, statistics, alerts |
| System admin | All of the above + settings (zones, hours, closures, auto-cancel) and staff/student accounts |
| Developer | Everything an admin can + center name and logo + alerts to supervisors and the admin |
| Follow-up only | Statistics and booking activity (view only) and messages to supervisors and the admin; no changes |

A system admin creates the first developer account once (Settings → management accounts); after that only a developer can create or change developer accounts. Permissions are enforced by the database itself, not just hidden in the UI.

### Automatic no-show cancellation

A server job runs every minute (pg_cron). If a student hasn't checked in 10 minutes (adjustable) after the hour starts, the booking is cancelled, the seat is freed, the student is notified, and supervisors get an alert under the 🔔 Alerts tab. Repeated no-shows (2 within 30 days by default) trigger an automatic warning and a supervisor alert. Adjust or switch this off in Settings. If pg_cron wasn't enabled during install, run `supabase/migrations/008_auto_no_show_schedule.sql`.

### Windows app (Windows 10/11)

Permanent download link: https://github.com/kss9393-OM/rec-center-booking/releases/download/windows-app/RecCenter-Setup.exe

Run `RecCenter-Setup.exe` and choose where to install; it adds a "مركز الترفيه الطلابي" shortcut to the desktop and Start menu. The installer isn't code-signed, so Windows may show "Windows protected your PC": click "More info", then "Run anyway". The app opens the live system, so website updates appear automatically. USB barcode scanners (keyboard mode) work in the Scan tab. GitHub Actions rebuilds the installer whenever the `windows/` folder changes.

### Android app (APK)
GitHub builds the app automatically on every change under `android/` and publishes it on the **Android app** release.
- **Permanent download link:** https://github.com/kss9393-OM/rec-center-booking/releases/latest/download/rec-center.apk
- **Install:** open the link on the device → download → open the file → allow installs from this source when asked → **Install**.
- **On Honeywell devices (e.g. EDA52):** the app reads the scanner directly, with no device setup. Other phones can scan with the camera.
- **Update:** download from the same link and install over the current version.
- **Signing:** the key file `android/keystore/crc-release.jks` is encrypted with a password kept only in **Settings → Secrets and variables → Actions** as `ANDROID_KEYSTORE_PASSWORD`. Keep a copy of the password somewhere safe; without it, updates can't be installed over the app.

### Ticket scanner (Honeywell EDA52 and similar devices)
**One-time device setup:** Settings → **Honeywell Settings** → **Scanning** → **Internal Scanner** → **Default Profile** → **Data Processing Settings**:
- **Wedge:** on.
- **Wedge Method:** Keyboard (or Standard).
- **Suffix:** `\n` (Enter after each scan) — recommended; the app also works without it.
- Make sure **QR Code** is enabled under **Symbology Settings** (it usually is).

**Use:** open the site in Chrome on the device → install it as an app → **Management** → sign in → **Scan** tab, then press the side scan button on the student's pass. Check-in happens instantly with a beep, vibration and a colour-coded result (green: done, amber: needs attention, red: refused).
If the code appears in the field but isn't submitted, add the `\n` suffix. If nothing appears, set Wedge Method to Keyboard.

### Install on Android
1. Open the site link in **Chrome** on the phone.
2. Tap **Install app** at the top of the page, or Chrome's menu (⋮) → **Install app** / **Add to Home screen**.
3. The app appears on the home screen with the college logo and opens full screen. Updates pushed to GitHub reach it automatically.

**On iPhone / iPad:** open the link in **Safari** → tap **Install app** at the top for the steps, or directly: Share → **Add to Home Screen** → **Add**. Reports and passes are saved through the Share sheet (Save to Files, AirDrop, …).

---

## License

Copyright © 2026 Services Squire LLC. All rights reserved.
No part of this software may be copied, modified, or distributed without written permission from Services Squire LLC.
