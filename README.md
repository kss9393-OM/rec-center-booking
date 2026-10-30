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

(أو عبر سطر الأوامر: `supabase functions deploy admin`)

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
- **الطالب:** يرى أعداد المقاعد فقط، ويرى حجوزاته ورسائله فقط.
- **موظف الاستقبال:** الحضور، والرسائل، والتقارير.
- **مدير النظام:** كل ما سبق، والإعدادات، والحسابات، وإصدار كلمات مرور مؤقتة للطلاب.
- قواعد الحجز (السعة، ساعة واحدة يومياً، أيام الإغلاق، انتهاء وقت الحجز) **يفرضها الخادم**، ولا يمكن تجاوزها من المتصفح.

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

(Or from the CLI: `supabase functions deploy admin`)

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
- **Student:** sees seat counts only, and only their own bookings and messages.
- **Reception staff:** check-ins, messages and reports.
- **System admin:** all of the above plus settings, accounts and temporary student passwords.
- Booking rules (capacity, one hour per day, closed days, booking cut-off) are **enforced by the server** and can't be bypassed from the browser.

---

## License

Copyright © 2026 Services Squire LLC. All rights reserved.
No part of this software may be copied, modified, or distributed without written permission from Services Squire LLC.
