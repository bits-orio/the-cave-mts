THE CAVE 3.2.38 — FORTIFIED ROOMS
Based only on the delivered and user-confirmed 3.2.37 branch.

نصب و تست
فایل the-cave_3.2.38.zip را بدون استخراج در پوشه mods قرار بده و همین نسخه
را فعال کن. ترکیب جدید برای غارهای تازه یا واردنشده است. غارهایی که قبلاً
واردشان شده‌ای، همان اتاق‌ها، دشمن‌ها و تایمر قبلی را تا بسته‌شدن نگه می‌دارند.
برای ساخت ورودی تازه کنار ادمین، فرمان قبلی همچنان در دسترس است:
/the-cave-fortified-vault-test

قواعد فعلی
۱۸ اتاق یکسان: ۲۵۰ در ۳۵ تایل، فاصله ردیف‌ها ۳۵ تایل آتاف‌مپ.
راهروی آبی ۳۵ در ۵۹۵ از ابتدا باز است و دشمن‌ها واردش نمی‌شوند.
فقط یک ورودی/خروجی بالا و یک Exit Only پایین راهروی آبی وجود دارد.
اتاق بعدی پس از کشتن تمام دشمن‌ها، لونه‌ها، کرم‌ها و تورت‌ها ساخته می‌شود.
برداشتن جعبه شرط پیشروی نیست. اتاق پاک‌شده امن می‌ماند.

                 سبز ۱–۶       زرد ۷–۱۲       قرمز ۱۳–۱۸
زمان هر اتاق      ۱۰ دقیقه      ۱۲ دقیقه       ۱۵ دقیقه
دشمن اولیه        ۳۰۰ آسان      ۲۵۰ متوسط      ۲۰۰ Big/Behemoth
لونه              ۱۲            ۱۲             ۱۲
کرم               ۱۰ آسان       ۱۰ متوسط       ۱۰ Big/Behemoth
گان تورت          ۶             ۴              ۴
لیزر تورت         ۰             ۴              ۴
فلیمر تورت        ۰             ۰              ۴
جعبه              ۸ آبی         ۶ زرد          ۴ قرمز

چهار خانواده: Biter، Spitter، Arachnid و Snapper، با سهم برابر و گردکردن لازم.
در زرد، سهم ۶۳/۶۳/۶۲/۶۲ بین اتاق‌ها جابه‌جا می‌شود تا جمع هر خانواده برابر باشد.
هر اتاق ۴ لونه آرکانید، ۴ اسنپر، ۲ بایتر و ۲ اسپیتر دارد.
تولید لونه‌ها جدا از دشمن‌های اولیه است؛ فاصله پایه ۲٫۵ / ۴٫۲۵ / ۶ ثانیه
است و یک تیک اختلاف طبیعی موتور بازی ممکن است. محدودیت جمعیت و جای خالی
خود Factorio همچنان اعمال می‌شود. Evolution بیرون غار این ترکیب را تغییر نمی‌دهد.
فشار از ورودی به سمت جعبه‌ها بیشتر می‌شود؛ فاصله مرکز لونه‌ها حداقل ۲۰ تایل
و فاصله مرکز تورت‌ها حداقل ۱۵ تایل است. کرم‌ها و تورت‌ها در بخش‌های پایانی‌اند.
جعبه‌ها تخریب‌ناپذیرند و کل بودجه آیتم‌های نسخه قبل حفظ شده است.

هر پلیر همزمان اضافه، ۵۰٪ تعداد پایه دشمن‌های متحرک را اضافه می‌کند.
مثال اتاق سبز: یک پلیر ۳۰۰، دو پلیر ۴۵۰، سه پلیر ۶۰۰، پنج پلیر ۹۰۰.
لونه‌ها، کرم‌ها و تورت‌ها ثابت می‌مانند. خروج پلیر باعث کم‌شدن تعداد یا
پرشدن دوباره دشمن‌های کشته‌شده نمی‌شود.
آتش فلیمر دشمن به نیروهای خودش آسیب نمی‌زند؛ آتش پلیر همچنان اثر دارد.
تایمر با خروج متوقف نمی‌شود. پس از پاکسازی اتاق ۱۸ هم وقت باقی‌مانده ادامه
دارد. در صفر، بازماندگان داخل می‌میرند و غار و آیتم‌های باقی‌مانده حذف می‌شوند.
نام مد The Cave است؛ برچسب‌های Stage 1 و PLAYTEST از عنوان و پنل‌ها حذف شده‌اند.

NATIVE VERIFICATION — Factorio 2.0.77, Base only
- Sequential progression through all 18 rooms, fixed static counts and native
  minimum spacing, four unit families/tiers, 108 protected caches and original
  item budgets, room timers and final-room remaining time.
- Population scaling fixtures for 2, 3 and 5 players; fixed nest identity/count,
  no refill of killed units, no downgrade on leaving; finite nest coin budgets.
- Native unit wall movement and collision/path tests, enemy exclusion from the
  blue hallway, cleared-room containment, deferred loot, and timeout cleanup.
- Current room-8 save reload and an actual 3.2.37 room-8 save upgrade; already
  entered rules/deadlines preserved, unentered old layouts upgraded lazily.
- 36 native nest fixtures across Evolution 0, 0.5 and 1 verified family/tier and
  measured spawn intervals (within one engine tick of the configured interval).
- 32 native fire cases, including real turret firing, friendly enemy units and
  defences, player damage, overlapping player/enemy ground fires in both creation
  orders, handheld player flame, and surviving fire after its source is removed.
- Production ZIP loaded by the native engine; archive CRC and source comparison.

LIMITS
No graphical client or connected human multiplayer combat session was run.
Progression uses scripted kills and simulated player/GUI interactions; player
count increases use scaling fixtures. Difficulty and full combat UPS still need
the user's normal playtest. Enemy ground fire uses force-filtered base damage;
this does not promise exact vanilla fuel-stack damage escalation. Player flame
prototypes and ordinary overworld units/nests are unchanged.
