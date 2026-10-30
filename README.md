# نظام حجز مركز الترفيه الطلابي · Campus Recreation Center Booking

© 2026 Services Squire LLC. جميع الحقوق محفوظة · All rights reserved.

---

## العربية

تطبيق ويب ثنائي اللغة (عربي / إنجليزي) لحجز ساعات وألعاب مركز الترفيه الطلابي، في ملف واحد `index.html`.

### المزايا
- **بوابة الطالب:** إنشاء حساب (الرقم الجامعي = اسم المستخدم + كلمة مرور)، حجز ساعة واحدة يومياً، تذكرة رقمية مع رمز QR، تعديل الحجز أو إلغاؤه، ومراسلة الإدارة.
- **الإدارة:** دخول باسم مستخدم وكلمة مرور بصلاحيتين (موظف استقبال / مدير نظام).
  - الاستقبال: عدّاد الإشغال، تسجيل الحضور وعدم الحضور، البحث، تصدير التقارير PDF وExcel.
  - الرسائل: محادثات ثنائية مع الطلاب.
  - الإعدادات (مدير النظام): اسم المركز وشعاره، الأقسام والسعة، الساعات، أيام الإغلاق، حسابات الموظفين، وإصدار كلمات مرور مؤقتة للطلاب.

### التشغيل
افتح `index.html` في المتصفح، أو فعّل GitHub Pages على هذا المستودع.

> **مهم:** عند التشغيل خارج Claude يعمل التطبيق في **الوضع التجريبي**؛ تُحفظ البيانات في متصفح الجهاز نفسه فقط (localStorage) ولا تُشارك بين الطلاب ومكتب الاستقبال. للتشغيل الفعلي متعدد الأجهزة يلزم ربطه بقاعدة بيانات خلفية (مثل Firebase أو Supabase).

---

## English

A bilingual (Arabic / English) single-file web app for booking hours and games at a campus recreation center.

### Features
- **Student portal:** account sign-up (student ID as username + password), one hour per day, digital pass with QR code, edit or cancel bookings, and messaging with staff.
- **Management:** username/password sign-in with two roles (reception staff / system admin).
  - Reception: live occupancy, check-in and no-show, search, PDF and Excel (CSV) reports.
  - Messages: two-way conversations with students.
  - Settings (admin): center name and logo, zones and capacity, opening hours, closed days, staff accounts, and temporary passwords for students.

### Running
Open `index.html` in a browser, or enable GitHub Pages for this repository.

> **Important:** outside Claude the app runs in **demo mode**: data is stored only in that device's browser (localStorage) and is not shared between students and the desk. A multi-device deployment needs a backend database (for example Firebase or Supabase).

---

## License

Copyright © 2026 Services Squire LLC. All rights reserved.
No part of this software may be copied, modified, or distributed without written permission from Services Squire LLC.
