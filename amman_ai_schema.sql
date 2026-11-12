-- =====================================================================
--  Amman AI — مخطط قاعدة البيانات الكامل
--  PostgreSQL 15+  (مُختبر على 16)  ·  يحتاج: pgvector, PostGIS, pg_trgm
--
--  التشغيل (على VPS هوستنجر):
--    1) CREATE DATABASE amman_ai;          -- قاعدة منفصلة عن قاعدة n8n الداخلية
--    2) psql -d amman_ai -v ON_ERROR_STOP=1 -f amman_ai_schema.sql
--
--  الملف آمن لإعادة التشغيل في أغلب أجزائه (IF NOT EXISTS / OR REPLACE).
--  العملة: الدينار الأردني بثلاث خانات عشرية (فلس) numeric(10,3).
--  المتجهات: 1536 بُعدًا (OpenAI text-embedding-3-small). غيّرها إن استخدمت نموذجًا آخر.
--
--  الأقسام:
--   0. الامتدادات والأدوار       7. الأحداث والتحليلات (events مقسّمة شهريًا)
--   1. الأنواع (Enums)           8. التجار، الاشتراكات، الإعلانات
--   2. دوال مساعدة               9. الاختبار (Eval)
--   3. الجغرافيا                10. دوال الوكيل (search_offers ...)
--                              10.5 سلّة العيلة + عدّاد التوفير
--   4. المتاجر والفئات           11. الصيانة (expire / trending / partitions)
--   5. الفلايرز والعروض          12. لوحات Metabase (Views + Materialized)
--   6. المستخدمون والمحادثات     13. الصلاحيات و RLS   ·   14. بيانات أولية
-- =====================================================================

BEGIN;

SET client_min_messages = warning;

-- =====================================================================
-- 0. الامتدادات والأدوار
-- =====================================================================
CREATE EXTENSION IF NOT EXISTS vector;     -- pgvector: البحث الدلالي
CREATE EXTENSION IF NOT EXISTS postgis;    -- المسافات والمحافظات
CREATE EXTENSION IF NOT EXISTS pg_trgm;    -- البحث التقريبي (أخطاء إملائية)

-- الأدوار تُنشأ بدون دخول (NOLOGIN). فعّلها بعد التشغيل بكلمة مرور قوية:
--   ALTER ROLE amman_app      LOGIN PASSWORD '...';   -- n8n (قراءة وكتابة)
--   ALTER ROLE amman_readonly LOGIN PASSWORD '...';   -- Metabase (قراءة فقط)
--   ALTER ROLE amman_merchant LOGIN PASSWORD '...';   -- بوابة التاجر (مقيّدة بـ RLS)
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'amman_app')      THEN CREATE ROLE amman_app NOLOGIN;      END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'amman_readonly') THEN CREATE ROLE amman_readonly NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'amman_merchant') THEN CREATE ROLE amman_merchant NOLOGIN; END IF;
END $$;

-- =====================================================================
-- 1. الأنواع (Enums)
-- =====================================================================
DO $$ BEGIN CREATE TYPE retailer_type AS ENUM
  ('hypermarket','supermarket','minimarket','consumer_coop','electronics','pharmacy',
   'furniture','fashion','beauty','kids','pets','online','other');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN CREATE TYPE offer_type AS ENUM
  ('price_cut','bogo','multi_buy','gift_with_purchase','bundle','clearance','other');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN CREATE TYPE offer_status AS ENUM ('draft','live','paused','expired','rejected');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN CREATE TYPE flyer_status AS ENUM
  ('uploaded','processing','review','live','paused','expired','rejected','failed');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN CREATE TYPE flyer_source AS ENUM ('portal','email','scrape','manual');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN CREATE TYPE channel_type AS ENUM ('in_store','online','delivery','phone_order');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN CREATE TYPE device_type AS ENUM ('web','pwa','ios','android','other');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN CREATE TYPE message_role AS ENUM ('user','assistant','system','tool');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN CREATE TYPE merchant_role AS ENUM ('owner','editor','viewer');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN CREATE TYPE plan_code AS ENUM ('free','pro','premium');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- =====================================================================
-- 2. دوال مساعدة
-- =====================================================================

-- تطبيع النص العربي للبحث: حذف التشكيل والتطويل، توحيد الألف/الياء/التاء المربوطة،
-- تحويل الأرقام الهندية إلى عربية (٠١٢ → 012)، وتوحيد المسافات.
CREATE OR REPLACE FUNCTION normalize_ar(t text)
RETURNS text LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
  SELECT btrim(regexp_replace(
           lower(translate(
             regexp_replace(coalesce(t, ''), '[ً-ٰٟـ]', '', 'g'),
             'أإآٱىةؤئ٠١٢٣٤٥٦٧٨٩٫،',
             'اااايهوي0123456789.,')),
           '\s+', ' ', 'g'))
$$;

-- معامل تحويل الوحدة إلى الوحدة الأساسية (غرام / مل / قطعة)
CREATE OR REPLACE FUNCTION unit_to_base(u text)
RETURNS numeric LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
  SELECT CASE lower(u)
           WHEN 'kg' THEN 1000 WHEN 'g' THEN 1
           WHEN 'l'  THEN 1000 WHEN 'ml' THEN 1
           ELSE 1 END::numeric
$$;

-- array_to_string مُعلنة STABLE في Postgres؛ لمصفوفة نصية هي ثابتة فعليًا، فنغلّفها لاستخدامها في الأعمدة المولّدة
CREATE OR REPLACE FUNCTION join_text(arr text[])
RETURNS text LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$ SELECT array_to_string(arr, ' ') $$;

-- تاريخ ووقت عمّان
CREATE OR REPLACE FUNCTION amman_now()   RETURNS timestamp LANGUAGE sql STABLE AS $$ SELECT now() AT TIME ZONE 'Asia/Amman' $$;
CREATE OR REPLACE FUNCTION amman_today() RETURNS date      LANGUAGE sql STABLE AS $$ SELECT (now() AT TIME ZONE 'Asia/Amman')::date $$;

-- updated_at تلقائي
CREATE OR REPLACE FUNCTION trg_set_updated_at()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at := now(); RETURN NEW; END $$;

-- هل الفرع مفتوح الآن؟
-- صيغة opening_hours:  {"24h": true}  أو
-- {"sat":[["08:00","23:00"]], "sun":[["08:00","23:00"]], ..., "fri":[["14:00","23:59"]]}
-- فترة تتجاوز منتصف الليل تُكتب ["20:00","02:00"].
CREATE OR REPLACE FUNCTION is_open_at(hours jsonb, at_ts timestamp DEFAULT amman_now())
RETURNS boolean LANGUAGE plpgsql STABLE AS $$
DECLARE
  d   text := (ARRAY['sun','mon','tue','wed','thu','fri','sat'])[extract(dow FROM at_ts)::int + 1];
  pd  text := (ARRAY['sun','mon','tue','wed','thu','fri','sat'])[extract(dow FROM at_ts - interval '1 day')::int + 1];
  t   time := at_ts::time;
  r   jsonb;
BEGIN
  IF hours IS NULL THEN RETURN NULL; END IF;
  IF (hours->>'24h')::boolean IS TRUE THEN RETURN TRUE; END IF;
  FOR r IN SELECT * FROM jsonb_array_elements(coalesce(hours->d, '[]')) LOOP
    IF (r->>0)::time <= (r->>1)::time THEN
      IF t BETWEEN (r->>0)::time AND (r->>1)::time THEN RETURN TRUE; END IF;
    ELSIF t >= (r->>0)::time THEN RETURN TRUE;           -- يتجاوز منتصف الليل (الجزء الأول)
    END IF;
  END LOOP;
  FOR r IN SELECT * FROM jsonb_array_elements(coalesce(hours->pd, '[]')) LOOP
    IF (r->>0)::time > (r->>1)::time AND t <= (r->>1)::time THEN RETURN TRUE; END IF;  -- بقية فترة الأمس
  END LOOP;
  RETURN FALSE;
END $$;

-- =====================================================================
-- 3. الجغرافيا
-- =====================================================================
CREATE TABLE IF NOT EXISTS governorates (
  id          smallint PRIMARY KEY,
  code        text UNIQUE NOT NULL,
  name_ar     text NOT NULL,
  name_en     text NOT NULL,
  aliases     text[] NOT NULL DEFAULT '{}',
  boundary    geography(MultiPolygon, 4326),       -- اختياري: حدود المحافظة لتحديدها من الموقع
  center      geography(Point, 4326)
);
CREATE INDEX IF NOT EXISTS governorates_boundary_gix ON governorates USING gist (boundary);

CREATE TABLE IF NOT EXISTS areas (
  id              serial PRIMARY KEY,
  governorate_id  smallint NOT NULL REFERENCES governorates(id),
  name_ar         text NOT NULL,
  name_en         text,
  aliases         text[] NOT NULL DEFAULT '{}',
  center          geography(Point, 4326),
  UNIQUE (governorate_id, name_ar)
);

-- تحديد المحافظة من إحداثيات (يحتاج تعبئة boundary، وإلا يرجع أقرب مركز)
CREATE OR REPLACE FUNCTION governorate_from_point(p_lat double precision, p_lng double precision)
RETURNS smallint LANGUAGE sql STABLE AS $$
  SELECT id FROM (
    SELECT id, 0 AS rk, 0::float8 AS dist FROM governorates
     WHERE boundary IS NOT NULL
       AND ST_Covers(boundary, ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography)
    UNION ALL
    SELECT id, 1, ST_Distance(center, ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography)
      FROM governorates WHERE center IS NOT NULL
  ) x ORDER BY rk, dist LIMIT 1
$$;

-- =====================================================================
-- 4. المتاجر والفروع والفئات والمنتجات
-- =====================================================================
CREATE TABLE IF NOT EXISTS retailers (
  id             bigserial PRIMARY KEY,
  slug           text UNIQUE NOT NULL,                  -- ctown, safeway, cozmo ...
  name_ar        text NOT NULL,
  name_en        text NOT NULL,
  aliases        text[] NOT NULL DEFAULT '{}',          -- سي تاون، سيتاون، ctown
  type           retailer_type NOT NULL DEFAULT 'supermarket',
  logo_url       text,
  website        text,
  online_store   text,
  phone          text,
  whatsapp       text,                                  -- رقم المتجر للتواصل (ليس قناة البوت)
  is_active      boolean NOT NULL DEFAULT true,
  is_partner     boolean NOT NULL DEFAULT false,        -- يرفع عبر البوابة
  plan           plan_code NOT NULL DEFAULT 'free',
  search_text    text GENERATED ALWAYS AS (
                   normalize_ar(name_ar || ' ' || name_en || ' ' || join_text(aliases))) STORED,
  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS retailers_search_trgm ON retailers USING gin (search_text gin_trgm_ops);
DROP TRIGGER IF EXISTS retailers_updated ON retailers;
CREATE TRIGGER retailers_updated BEFORE UPDATE ON retailers FOR EACH ROW EXECUTE FUNCTION trg_set_updated_at();

CREATE TABLE IF NOT EXISTS branches (
  id              bigserial PRIMARY KEY,
  retailer_id     bigint NOT NULL REFERENCES retailers(id) ON DELETE CASCADE,
  name_ar         text NOT NULL,
  governorate_id  smallint NOT NULL REFERENCES governorates(id),
  area_id         int REFERENCES areas(id),
  address         text,
  geo             geography(Point, 4326),
  opening_hours   jsonb,
  phone           text,
  maps_url        text,
  is_active       boolean NOT NULL DEFAULT true,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS branches_retailer_idx ON branches (retailer_id) WHERE is_active;
CREATE INDEX IF NOT EXISTS branches_gov_idx      ON branches (governorate_id);
CREATE INDEX IF NOT EXISTS branches_geo_gix      ON branches USING gist (geo);
DROP TRIGGER IF EXISTS branches_updated ON branches;
CREATE TRIGGER branches_updated BEFORE UPDATE ON branches FOR EACH ROW EXECUTE FUNCTION trg_set_updated_at();

CREATE TABLE IF NOT EXISTS categories (
  id          serial PRIMARY KEY,
  parent_id   int REFERENCES categories(id),
  slug        text UNIQUE NOT NULL,
  name_ar     text NOT NULL,
  name_en     text NOT NULL,
  synonyms    text[] NOT NULL DEFAULT '{}',
  sort_order  int NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS categories_parent_idx ON categories (parent_id);

-- كتالوج المنتجات الموحّد (لربط نفس المنتج عبر المتاجر للمقارنة وسجل الأسعار)
CREATE TABLE IF NOT EXISTS products (
  id            bigserial PRIMARY KEY,
  name_ar       text NOT NULL,
  name_en       text,
  brand         text,
  category_id   int REFERENCES categories(id),
  size_value    numeric(10,3),
  size_unit     text CHECK (size_unit IN ('g','kg','ml','l','pcs','pack')),
  barcode       text UNIQUE,
  image_url     text,
  embedding     vector(1536),
  search_text   text GENERATED ALWAYS AS (
                  normalize_ar(name_ar || ' ' || coalesce(name_en, '') || ' ' || coalesce(brand, ''))) STORED,
  created_at    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS products_search_trgm ON products USING gin (search_text gin_trgm_ops);
CREATE INDEX IF NOT EXISTS products_brand_idx   ON products (lower(brand));
CREATE INDEX IF NOT EXISTS products_emb_hnsw    ON products USING hnsw (embedding vector_cosine_ops);

CREATE TABLE IF NOT EXISTS campaigns (
  id         serial PRIMARY KEY,
  slug       text UNIQUE NOT NULL,                     -- ramadan, eid_fitr, back_to_school, white_friday
  name_ar    text NOT NULL,
  name_en    text NOT NULL,
  starts_on  date,
  ends_on    date
);

-- =====================================================================
-- 5. الفلايرز والعروض
-- =====================================================================
CREATE TABLE IF NOT EXISTS merchant_users (       -- مستخدمو بوابة التاجر (الحساب نفسه في Better Auth)
  id             bigserial PRIMARY KEY,
  auth_user_id   text UNIQUE,                      -- معرّف Better Auth
  retailer_id    bigint NOT NULL REFERENCES retailers(id) ON DELETE CASCADE,
  name           text NOT NULL,
  email          text UNIQUE NOT NULL,
  phone          text,
  role           merchant_role NOT NULL DEFAULT 'editor',
  is_active      boolean NOT NULL DEFAULT true,
  last_login_at  timestamptz,
  created_at     timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS merchant_users_retailer_idx ON merchant_users (retailer_id);

CREATE TABLE IF NOT EXISTS flyers (
  id                     bigserial PRIMARY KEY,
  retailer_id            bigint NOT NULL REFERENCES retailers(id) ON DELETE CASCADE,
  title                  text,
  valid_from             date NOT NULL,
  valid_to               date NOT NULL,
  governorate_ids        smallint[] NOT NULL DEFAULT '{}',   -- فارغ = كل المحافظات
  branch_ids             bigint[]   NOT NULL DEFAULT '{}',   -- فارغ = كل الفروع
  campaign_id            int REFERENCES campaigns(id),
  channels               channel_type[] NOT NULL DEFAULT '{in_store}',
  source                 flyer_source NOT NULL DEFAULT 'portal',
  source_url             text,
  source_hash            text UNIQUE,                        -- sha256 للملف لمنع التكرار
  file_url               text,
  page_count             int,
  status                 flyer_status NOT NULL DEFAULT 'uploaded',
  uploaded_by            bigint REFERENCES merchant_users(id),
  offers_extracted       int NOT NULL DEFAULT 0,
  offers_edited          int NOT NULL DEFAULT 0,             -- مقياس دقة الاستخراج
  processing_started_at  timestamptz,
  processing_finished_at timestamptz,
  published_at           timestamptz,
  error                  text,
  created_at             timestamptz NOT NULL DEFAULT now(),
  updated_at             timestamptz NOT NULL DEFAULT now(),
  CHECK (valid_to >= valid_from)
);
CREATE INDEX IF NOT EXISTS flyers_retailer_idx ON flyers (retailer_id, valid_to DESC);
CREATE INDEX IF NOT EXISTS flyers_status_idx   ON flyers (status);
DROP TRIGGER IF EXISTS flyers_updated ON flyers;
CREATE TRIGGER flyers_updated BEFORE UPDATE ON flyers FOR EACH ROW EXECUTE FUNCTION trg_set_updated_at();

CREATE TABLE IF NOT EXISTS flyer_pages (
  id                 bigserial PRIMARY KEY,
  flyer_id           bigint NOT NULL REFERENCES flyers(id) ON DELETE CASCADE,
  page_no            int NOT NULL,
  image_url          text NOT NULL,
  width              int,
  height             int,
  extraction_status  text NOT NULL DEFAULT 'pending' CHECK (extraction_status IN ('pending','done','failed')),
  raw_extraction     jsonb,                 -- مخرج نموذج Vision كما هو (للمراجعة وإعادة المعالجة)
  model              text,
  cost_usd           numeric(10,5),
  UNIQUE (flyer_id, page_no)
);

CREATE TABLE IF NOT EXISTS offers (
  id                  bigserial PRIMARY KEY,
  flyer_id            bigint REFERENCES flyers(id) ON DELETE CASCADE,
  flyer_page_id       bigint REFERENCES flyer_pages(id) ON DELETE SET NULL,
  retailer_id         bigint NOT NULL REFERENCES retailers(id) ON DELETE CASCADE,
  product_id          bigint REFERENCES products(id),
  product_name_ar     text NOT NULL,
  product_name_en     text,
  brand               text,
  category_id         int REFERENCES categories(id),
  size_value          numeric(10,3),
  size_unit           text CHECK (size_unit IN ('g','kg','ml','l','pcs','pack')),
  pack_count          int NOT NULL DEFAULT 1 CHECK (pack_count > 0),   -- 6 × 1.5 لتر → size 1.5 l, pack 6
  size_label          text,                                            -- النص كما في الفلاير
  price_jod           numeric(10,3) NOT NULL CHECK (price_jod >= 0),
  old_price_jod       numeric(10,3) CHECK (old_price_jod IS NULL OR old_price_jod >= 0),
  discount_pct        numeric(5,1) GENERATED ALWAYS AS (
                        CASE WHEN old_price_jod > 0 AND old_price_jod > price_jod
                             THEN round((old_price_jod - price_jod) / old_price_jod * 100, 1) END) STORED,
  -- سعر الكيلو / اللتر / القطعة
  unit_price          numeric(12,4) GENERATED ALWAYS AS (
                        CASE WHEN size_value > 0 THEN round(
                          price_jod / (size_value * unit_to_base(size_unit) * pack_count)
                          * CASE WHEN size_unit IN ('g','kg','ml','l') THEN 1000 ELSE 1 END, 4) END) STORED,
  unit_label          text GENERATED ALWAYS AS (
                        CASE WHEN size_unit IN ('g','kg') THEN 'kg'
                             WHEN size_unit IN ('ml','l') THEN 'l'
                             WHEN size_unit IS NOT NULL THEN 'pcs' END) STORED,
  offer_type          offer_type NOT NULL DEFAULT 'price_cut',
  offer_note          text,                                  -- "1+1" ، "اشترِ 2 وخذ 1"
  valid_from          date NOT NULL,
  valid_to            date NOT NULL,
  governorate_ids     smallint[] NOT NULL DEFAULT '{}',      -- فارغ = كل المملكة
  branch_ids          bigint[]   NOT NULL DEFAULT '{}',
  channels            channel_type[] NOT NULL DEFAULT '{in_store}',
  campaign_id         int REFERENCES campaigns(id),
  online_url          text,
  image_url           text,                                  -- صورة العرض المقصوصة
  bbox                int[] CHECK (bbox IS NULL OR array_length(bbox, 1) = 4),
  confidence          numeric(3,2) CHECK (confidence BETWEEN 0 AND 1),
  status              offer_status NOT NULL DEFAULT 'draft',
  is_sponsored        boolean NOT NULL DEFAULT false,
  edited_by_merchant  boolean NOT NULL DEFAULT false,
  embedding           vector(1536),
  search_text         text GENERATED ALWAYS AS (
                        normalize_ar(product_name_ar || ' ' || coalesce(product_name_en, '') || ' ' ||
                                     coalesce(brand, '') || ' ' || coalesce(size_label, ''))) STORED,
  views               int NOT NULL DEFAULT 0,
  clicks              int NOT NULL DEFAULT 0,
  saves               int NOT NULL DEFAULT 0,
  trend_score         numeric(12,3) NOT NULL DEFAULT 0,
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now(),
  CHECK (valid_to >= valid_from)
);
CREATE INDEX IF NOT EXISTS offers_live_idx      ON offers (valid_to, valid_from) WHERE status = 'live';
CREATE INDEX IF NOT EXISTS offers_retailer_idx  ON offers (retailer_id) WHERE status = 'live';
CREATE INDEX IF NOT EXISTS offers_category_idx  ON offers (category_id) WHERE status = 'live';
CREATE INDEX IF NOT EXISTS offers_brand_idx     ON offers (lower(brand)) WHERE status = 'live';
CREATE INDEX IF NOT EXISTS offers_product_idx   ON offers (product_id);
CREATE INDEX IF NOT EXISTS offers_flyer_idx     ON offers (flyer_id);
CREATE INDEX IF NOT EXISTS offers_gov_gin       ON offers USING gin (governorate_ids);
CREATE INDEX IF NOT EXISTS offers_search_trgm   ON offers USING gin (search_text gin_trgm_ops);
CREATE INDEX IF NOT EXISTS offers_emb_hnsw      ON offers USING hnsw (embedding vector_cosine_ops);
CREATE INDEX IF NOT EXISTS offers_trend_idx     ON offers (trend_score DESC) WHERE status = 'live';
DROP TRIGGER IF EXISTS offers_updated ON offers;
CREATE TRIGGER offers_updated BEFORE UPDATE ON offers FOR EACH ROW EXECUTE FUNCTION trg_set_updated_at();

-- العرض يرث من الفلاير: المتجر، التواريخ، المحافظات، القنوات (إن لم تُحدد)
CREATE OR REPLACE FUNCTION trg_offer_defaults()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE f flyers%ROWTYPE;
BEGIN
  IF NEW.flyer_id IS NOT NULL THEN
    SELECT * INTO f FROM flyers WHERE id = NEW.flyer_id;
    NEW.retailer_id     := coalesce(NEW.retailer_id, f.retailer_id);
    NEW.valid_from      := coalesce(NEW.valid_from, f.valid_from);
    NEW.valid_to        := coalesce(NEW.valid_to, f.valid_to);
    NEW.campaign_id     := coalesce(NEW.campaign_id, f.campaign_id);
    IF NEW.governorate_ids = '{}' THEN NEW.governorate_ids := f.governorate_ids; END IF;
    IF NEW.branch_ids      = '{}' THEN NEW.branch_ids      := f.branch_ids;      END IF;
  END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS offers_defaults ON offers;
CREATE TRIGGER offers_defaults BEFORE INSERT ON offers FOR EACH ROW EXECUTE FUNCTION trg_offer_defaults();

-- سجل الأسعار (هل العرض حقيقي؟ أدنى سعر خلال 90 يومًا)
CREATE TABLE IF NOT EXISTS price_history (
  id             bigserial PRIMARY KEY,
  product_id     bigint NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  retailer_id    bigint NOT NULL REFERENCES retailers(id) ON DELETE CASCADE,
  offer_id       bigint REFERENCES offers(id) ON DELETE SET NULL,
  price_jod      numeric(10,3) NOT NULL,
  old_price_jod  numeric(10,3),
  observed_on    date NOT NULL DEFAULT amman_today(),
  UNIQUE (product_id, retailer_id, observed_on)
);
CREATE INDEX IF NOT EXISTS price_history_lookup ON price_history (product_id, observed_on DESC);

CREATE OR REPLACE FUNCTION trg_offer_price_history()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.status = 'live' AND NEW.product_id IS NOT NULL THEN
    INSERT INTO price_history (product_id, retailer_id, offer_id, price_jod, old_price_jod, observed_on)
    VALUES (NEW.product_id, NEW.retailer_id, NEW.id, NEW.price_jod, NEW.old_price_jod, amman_today())
    ON CONFLICT (product_id, retailer_id, observed_on)
    DO UPDATE SET price_jod = LEAST(price_history.price_jod, EXCLUDED.price_jod), offer_id = EXCLUDED.offer_id;
  END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS offers_price_history ON offers;
CREATE TRIGGER offers_price_history AFTER INSERT OR UPDATE OF status, price_jod ON offers
  FOR EACH ROW EXECUTE FUNCTION trg_offer_price_history();

CREATE TABLE IF NOT EXISTS coupons (
  id            bigserial PRIMARY KEY,
  retailer_id   bigint NOT NULL REFERENCES retailers(id) ON DELETE CASCADE,
  code          text NOT NULL,
  description   text,
  discount_text text,                          -- "15% على أول طلب"
  category_id   int REFERENCES categories(id),
  min_order_jod numeric(10,3),
  valid_from    date NOT NULL DEFAULT amman_today(),
  valid_to      date,
  url           text,
  is_active     boolean NOT NULL DEFAULT true,
  created_at    timestamptz NOT NULL DEFAULT now(),
  UNIQUE (retailer_id, code)
);

-- =====================================================================
-- 6. المستخدمون والمحادثات والقوائم والتنبيهات
-- =====================================================================
-- ملاحظة: Better Auth ينشئ جداوله الخاصة ("user", "session", "account" ...).
-- لذلك جدولنا اسمه app_users ويرتبط بها عبر auth_user_id.
CREATE TABLE IF NOT EXISTS app_users (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  auth_user_id        text UNIQUE,                  -- NULL للزائر
  anon_id             text UNIQUE,                  -- معرّف الزائر من المتصفح (قبل التسجيل)
  is_guest            boolean NOT NULL DEFAULT true,
  display_name        text,
  email               text,
  phone               text,                         -- قد تحتاج تشفيره حسب قانون حماية البيانات
  phone_hash          text,
  signup_method       text CHECK (signup_method IN ('google','apple','phone','email')),
  language            text NOT NULL DEFAULT 'ar' CHECK (language IN ('ar','en')),
  governorate_id      smallint REFERENCES governorates(id),
  area_id             int REFERENCES areas(id),
  geo                 geography(Point, 4326),       -- آخر موقع شاركه (اختياري)
  favorite_retailers  bigint[] NOT NULL DEFAULT '{}',
  notify_prefs        jsonb NOT NULL DEFAULT '{"push": true, "email": false, "weekly_digest": true, "max_per_day": 3}',
  marketing_consent   boolean NOT NULL DEFAULT false,
  consent_at          timestamptz,
  first_device        device_type,
  utm_source          text,
  signed_up_at        timestamptz,
  last_seen_at        timestamptz,
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now(),
  deleted_at          timestamptz                    -- حذف الحساب (تُمسح البيانات الشخصية)
);
CREATE INDEX IF NOT EXISTS app_users_gov_idx      ON app_users (governorate_id);
CREATE INDEX IF NOT EXISTS app_users_last_seen    ON app_users (last_seen_at DESC);
CREATE INDEX IF NOT EXISTS app_users_email_idx    ON app_users (lower(email));
DROP TRIGGER IF EXISTS app_users_updated ON app_users;
CREATE TRIGGER app_users_updated BEFORE UPDATE ON app_users FOR EACH ROW EXECUTE FUNCTION trg_set_updated_at();

CREATE TABLE IF NOT EXISTS push_subscriptions (     -- Web Push / FCM
  id           bigserial PRIMARY KEY,
  user_id      uuid NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
  device       device_type NOT NULL DEFAULT 'web',
  endpoint     text NOT NULL UNIQUE,
  keys         jsonb,
  created_at   timestamptz NOT NULL DEFAULT now(),
  last_ok_at   timestamptz,
  is_active    boolean NOT NULL DEFAULT true
);

CREATE TABLE IF NOT EXISTS conversations (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      uuid NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
  title        text,
  filters      jsonb NOT NULL DEFAULT '{}',   -- آخر فلاتر فعّالة (يقرؤها الوكيل)
  is_archived  boolean NOT NULL DEFAULT false,
  share_token  text UNIQUE,                   -- مشاركة المحادثة
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS conversations_user_idx ON conversations (user_id, updated_at DESC) WHERE NOT is_archived;
DROP TRIGGER IF EXISTS conversations_updated ON conversations;
CREATE TRIGGER conversations_updated BEFORE UPDATE ON conversations FOR EACH ROW EXECUTE FUNCTION trg_set_updated_at();

CREATE TABLE IF NOT EXISTS messages (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id  uuid NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  role             message_role NOT NULL,
  content          text NOT NULL DEFAULT '',
  attachments      jsonb NOT NULL DEFAULT '[]',   -- [{type:"image"|"audio", url, transcript}]
  input_type       text CHECK (input_type IN ('text','voice','image','chip')),
  feedback         smallint CHECK (feedback IN (-1, 1)),
  feedback_reason  text,
  feedback_at      timestamptz,
  model            text,
  latency_ms       int,
  created_at       timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS messages_conv_idx     ON messages (conversation_id, created_at);
CREATE INDEX IF NOT EXISTS messages_feedback_idx ON messages (feedback_at DESC) WHERE feedback IS NOT NULL;

-- تحديث وقت المحادثة عند كل رسالة
CREATE OR REPLACE FUNCTION trg_touch_conversation()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN UPDATE conversations SET updated_at = now() WHERE id = NEW.conversation_id; RETURN NEW; END $$;
DROP TRIGGER IF EXISTS messages_touch ON messages;
CREATE TRIGGER messages_touch AFTER INSERT ON messages FOR EACH ROW EXECUTE FUNCTION trg_touch_conversation();

-- بطاقات العروض المعروضة تحت كل رد (تُجلب بعد انتهاء البث)
CREATE TABLE IF NOT EXISTS message_offers (
  message_id  uuid NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
  position    smallint NOT NULL,                 -- "العرض 1" في نص الرد
  offer_id    bigint NOT NULL REFERENCES offers(id) ON DELETE CASCADE,
  PRIMARY KEY (message_id, position)
);
CREATE INDEX IF NOT EXISTS message_offers_offer_idx ON message_offers (offer_id);

-- ذاكرة وكيل n8n (عقدة Postgres Chat Memory تنشئه تلقائيًا بنفس البنية؛ هنا مُسبقًا مع فهرس)
CREATE TABLE IF NOT EXISTS n8n_chat_histories (
  id          serial PRIMARY KEY,
  session_id  varchar(255) NOT NULL,          -- user_id:conversation_id
  message     jsonb NOT NULL
);
CREATE INDEX IF NOT EXISTS n8n_chat_histories_session_idx ON n8n_chat_histories (session_id, id);

CREATE TABLE IF NOT EXISTS shopping_lists (
  id           bigserial PRIMARY KEY,
  user_id      uuid NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
  name         text NOT NULL DEFAULT 'قائمتي',
  is_default   boolean NOT NULL DEFAULT true,
  share_token  text UNIQUE,
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS shopping_lists_one_default ON shopping_lists (user_id) WHERE is_default;

CREATE TABLE IF NOT EXISTS list_items (
  id            bigserial PRIMARY KEY,
  list_id       bigint NOT NULL REFERENCES shopping_lists(id) ON DELETE CASCADE,
  offer_id      bigint REFERENCES offers(id) ON DELETE SET NULL,
  free_text     text,                                -- "خبز" بدون عرض محدد
  qty           numeric(8,2) NOT NULL DEFAULT 1 CHECK (qty > 0),
  price_at_add  numeric(10,3),                       -- لحساب التوفير المقدّر
  saved_at_add  numeric(10,3),                       -- old_price - price وقت الإضافة
  is_checked    boolean NOT NULL DEFAULT false,
  added_from    text CHECK (added_from IN ('chat','card_button','manual')),
  created_at    timestamptz NOT NULL DEFAULT now(),
  CHECK (offer_id IS NOT NULL OR free_text IS NOT NULL)
);
CREATE INDEX IF NOT EXISTS list_items_list_idx ON list_items (list_id);

CREATE TABLE IF NOT EXISTS alerts (
  id                 bigserial PRIMARY KEY,
  user_id            uuid NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
  query              text,
  query_norm         text GENERATED ALWAYS AS (normalize_ar(query)) STORED,
  product_id         bigint REFERENCES products(id),
  brand              text,
  category_id        int REFERENCES categories(id),
  retailer_ids       bigint[] NOT NULL DEFAULT '{}',
  governorate_id     smallint REFERENCES governorates(id),
  target_price_jod   numeric(10,3),
  min_discount_pct   numeric(5,1),
  is_active          boolean NOT NULL DEFAULT true,
  last_triggered_at  timestamptz,
  created_at         timestamptz NOT NULL DEFAULT now(),
  CHECK (query IS NOT NULL OR product_id IS NOT NULL OR brand IS NOT NULL OR category_id IS NOT NULL)
);
CREATE INDEX IF NOT EXISTS alerts_active_idx ON alerts (is_active) WHERE is_active;
CREATE INDEX IF NOT EXISTS alerts_query_trgm ON alerts USING gin (query_norm gin_trgm_ops);

CREATE TABLE IF NOT EXISTS alert_notifications (
  id          bigserial PRIMARY KEY,
  alert_id    bigint NOT NULL REFERENCES alerts(id) ON DELETE CASCADE,
  offer_id    bigint NOT NULL REFERENCES offers(id) ON DELETE CASCADE,
  sent_at     timestamptz NOT NULL DEFAULT now(),
  channel     text NOT NULL DEFAULT 'push' CHECK (channel IN ('push','email','in_chat')),
  opened_at   timestamptz,
  UNIQUE (alert_id, offer_id)                       -- لا يُرسل نفس العرض مرتين
);

CREATE TABLE IF NOT EXISTS offer_ratings (
  offer_id    bigint NOT NULL REFERENCES offers(id) ON DELETE CASCADE,
  user_id     uuid NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
  rating      smallint NOT NULL CHECK (rating BETWEEN 1 AND 5),
  comment     text,
  created_at  timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (offer_id, user_id)
);

CREATE TABLE IF NOT EXISTS offer_reports (
  id           bigserial PRIMARY KEY,
  offer_id     bigint NOT NULL REFERENCES offers(id) ON DELETE CASCADE,
  user_id      uuid REFERENCES app_users(id) ON DELETE SET NULL,
  reason       text NOT NULL CHECK (reason IN ('not_in_store','wrong_price','expired','wrong_product','other')),
  details      text,
  status       text NOT NULL DEFAULT 'open' CHECK (status IN ('open','confirmed','dismissed')),
  created_at   timestamptz NOT NULL DEFAULT now(),
  resolved_at  timestamptz
);
CREATE INDEX IF NOT EXISTS offer_reports_open_idx ON offer_reports (status, created_at) WHERE status = 'open';

-- =====================================================================
-- 7. الأحداث والتحليلات
-- =====================================================================
-- جدول أحداث واحد مقسّم شهريًا. الواجهة والوكيل يكتبان فيه، ولوحة الشركة تقرأ منه.
-- أسماء الأحداث المعتمدة:
--   visit, session_start, signup, login, message_sent, search_performed, zero_results,
--   offer_impression, offer_click, list_add, list_remove, directions_click, store_contact,
--   share, alert_created, push_sent, push_opened, feedback, offer_reported, flyer_view
CREATE SEQUENCE IF NOT EXISTS events_id_seq;
CREATE TABLE IF NOT EXISTS events (
  id               bigint NOT NULL DEFAULT nextval('events_id_seq'),
  created_at       timestamptz NOT NULL DEFAULT now(),
  event_name       text NOT NULL,
  user_id          uuid,                 -- بدون FK عمدًا (سرعة الكتابة + بقاء الإحصاء بعد حذف الحساب)
  anon_id          text,
  session_id       text,
  conversation_id  uuid,
  message_id       uuid,
  governorate_id   smallint,
  area_id          int,
  device           device_type,
  browser          text,
  app_version      text,
  utm_source       text,
  utm_medium       text,
  utm_campaign     text,
  retailer_id      bigint,               -- منسوخة من props لتسهيل التجميع
  offer_id         bigint,
  category_id      int,
  props            jsonb NOT NULL DEFAULT '{}',
  PRIMARY KEY (id, created_at)
) PARTITION BY RANGE (created_at);
CREATE TABLE IF NOT EXISTS events_default PARTITION OF events DEFAULT;
CREATE INDEX IF NOT EXISTS events_name_time_idx ON events (event_name, created_at);
CREATE INDEX IF NOT EXISTS events_user_time_idx ON events (user_id, created_at);
CREATE INDEX IF NOT EXISTS events_retailer_idx  ON events (retailer_id, created_at) WHERE retailer_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS events_offer_idx     ON events (offer_id, created_at)    WHERE offer_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS events_gov_idx       ON events (governorate_id, created_at);

-- تكلفة وجودة كل رد للوكيل (يكتبه WF4)
CREATE TABLE IF NOT EXISTS agent_turns (
  id               bigserial PRIMARY KEY,
  created_at       timestamptz NOT NULL DEFAULT now(),
  user_id          uuid,
  conversation_id  uuid,
  message_id       uuid,
  model            text,
  prompt_version   text,
  intent           text,
  tools_used       text[] NOT NULL DEFAULT '{}',
  tool_params      jsonb,
  results_count    int,
  latency_ms       int,
  tokens_in        int,
  tokens_out       int,
  cost_usd         numeric(10,6),
  error            text
);
CREATE INDEX IF NOT EXISTS agent_turns_time_idx   ON agent_turns (created_at);
CREATE INDEX IF NOT EXISTS agent_turns_intent_idx ON agent_turns (intent, created_at);

-- =====================================================================
-- 8. التجار: الاشتراكات، الإعلانات الممولة، الفواتير
-- =====================================================================
CREATE TABLE IF NOT EXISTS subscriptions (
  id            bigserial PRIMARY KEY,
  retailer_id   bigint NOT NULL REFERENCES retailers(id) ON DELETE CASCADE,
  plan          plan_code NOT NULL,
  amount_jod    numeric(10,3) NOT NULL DEFAULT 0,
  billing       text NOT NULL DEFAULT 'monthly' CHECK (billing IN ('monthly','yearly')),
  starts_on     date NOT NULL,
  ends_on       date,
  status        text NOT NULL DEFAULT 'active' CHECK (status IN ('trial','active','past_due','cancelled')),
  created_at    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS subscriptions_retailer_idx ON subscriptions (retailer_id, starts_on DESC);

CREATE TABLE IF NOT EXISTS sponsored_slots (
  id               bigserial PRIMARY KEY,
  retailer_id      bigint NOT NULL REFERENCES retailers(id) ON DELETE CASCADE,
  offer_id         bigint REFERENCES offers(id) ON DELETE CASCADE,
  category_id      int REFERENCES categories(id),
  governorate_ids  smallint[] NOT NULL DEFAULT '{}',
  starts_at        timestamptz NOT NULL,
  ends_at          timestamptz NOT NULL,
  budget_jod       numeric(10,3),
  price_model      text NOT NULL DEFAULT 'flat' CHECK (price_model IN ('flat','cpm','cpc')),
  impressions      int NOT NULL DEFAULT 0,
  clicks           int NOT NULL DEFAULT 0,
  created_at       timestamptz NOT NULL DEFAULT now(),
  CHECK (ends_at > starts_at)
);

CREATE TABLE IF NOT EXISTS invoices (
  id            bigserial PRIMARY KEY,
  retailer_id   bigint NOT NULL REFERENCES retailers(id) ON DELETE CASCADE,
  number        text UNIQUE NOT NULL,
  issued_on     date NOT NULL DEFAULT amman_today(),
  amount_jod    numeric(10,3) NOT NULL,
  tax_jod       numeric(10,3) NOT NULL DEFAULT 0,
  status        text NOT NULL DEFAULT 'unpaid' CHECK (status IN ('unpaid','paid','void')),
  items         jsonb NOT NULL DEFAULT '[]',
  paid_at       timestamptz
);

-- =====================================================================
-- 9. اختبار الوكيل (WF6)
-- =====================================================================
CREATE TABLE IF NOT EXISTS eval_cases (
  id               serial PRIMARY KEY,
  intent           text NOT NULL,
  language         text NOT NULL DEFAULT 'ar-JO',   -- ar-JO, ar, en, arabizi
  turns            jsonb NOT NULL,                  -- ["عروض حفاضات","بس بامبرز مقاس 5"]
  expected_tool    text,
  expected_params  jsonb,                           -- الفلاتر المتوقعة في آخر جولة
  notes            text,
  is_active        boolean NOT NULL DEFAULT true
);
CREATE TABLE IF NOT EXISTS eval_runs (
  id              serial PRIMARY KEY,
  started_at      timestamptz NOT NULL DEFAULT now(),
  model           text,
  prompt_version  text,
  total           int,
  passed          int
);
CREATE TABLE IF NOT EXISTS eval_results (
  run_id         int NOT NULL REFERENCES eval_runs(id) ON DELETE CASCADE,
  case_id        int NOT NULL REFERENCES eval_cases(id) ON DELETE CASCADE,
  passed         boolean NOT NULL,
  actual_tool    text,
  actual_params  jsonb,
  diff           jsonb,
  PRIMARY KEY (run_id, case_id)
);

-- =====================================================================
-- 10. دوال الوكيل (تُستدعى من workflows الأدوات في n8n بمعاملات، لا SQL حر)
-- =====================================================================

-- search_offers: كل فلاتر ClickFlyer في دالة واحدة.
-- مثال من n8n (Postgres node, Query Parameters):
--   SELECT * FROM search_offers(p_query => $1, p_governorate_id => $2::smallint,
--                               p_discount_min => $3, p_sort => 'unit_price', p_limit => 5);
CREATE OR REPLACE FUNCTION search_offers(
  p_query             text            DEFAULT NULL,
  p_embedding         vector          DEFAULT NULL,   -- متجه السؤال (اختياري، للبحث الدلالي)
  p_brand             text            DEFAULT NULL,
  p_category_ids      int[]           DEFAULT NULL,   -- تشمل الفئات الفرعية تلقائيًا
  p_retailer_ids      bigint[]        DEFAULT NULL,
  p_retailer_types    retailer_type[] DEFAULT NULL,
  p_governorate_id    smallint        DEFAULT NULL,
  p_lat               double precision DEFAULT NULL,
  p_lng               double precision DEFAULT NULL,
  p_radius_km         numeric         DEFAULT NULL,
  p_discount_min      numeric         DEFAULT NULL,
  p_discount_max      numeric         DEFAULT NULL,
  p_price_min         numeric         DEFAULT NULL,
  p_price_max         numeric         DEFAULT NULL,
  p_offer_types       offer_type[]    DEFAULT NULL,
  p_valid_on          date            DEFAULT NULL,   -- NULL = اليوم
  p_ends_within_days  int             DEFAULT NULL,
  p_include_upcoming  boolean         DEFAULT false,  -- عروض تبدأ خلال 3 أيام
  p_campaign          text            DEFAULT NULL,   -- slug
  p_channels          channel_type[]  DEFAULT NULL,
  p_has_coupon        boolean         DEFAULT NULL,
  p_size_value        numeric         DEFAULT NULL,
  p_size_unit         text            DEFAULT NULL,
  p_min_rating        numeric         DEFAULT NULL,
  p_favorites_of      uuid            DEFAULT NULL,   -- user_id → متاجره المفضلة فقط
  p_open_now          boolean         DEFAULT NULL,
  p_sort              text            DEFAULT 'relevance',
     -- relevance | price_asc | price_desc | unit_price | discount | ending_soon | newest | popularity | distance | alpha
  p_limit             int             DEFAULT 10,
  p_offset            int             DEFAULT 0
)
RETURNS TABLE (
  offer_id        bigint,
  product_name_ar text,
  product_name_en text,
  brand           text,
  size_label      text,
  price_jod       numeric,
  old_price_jod   numeric,
  discount_pct    numeric,
  unit_price      numeric,
  unit_label      text,
  offer_type      offer_type,
  offer_note      text,
  retailer_id     bigint,
  retailer_name   text,
  valid_from      date,
  valid_to        date,
  days_left       int,
  channels        channel_type[],
  image_url       text,
  online_url      text,
  is_sponsored    boolean,
  distance_km     numeric,
  nearest_branch  bigint,
  score           numeric,
  total_count     bigint
)
LANGUAGE sql STABLE
SET pg_trgm.word_similarity_threshold = 0.4
AS $$
WITH params AS (
  SELECT normalize_ar(p_query)                                         AS nq,
         coalesce(p_valid_on, amman_today())                           AS d,
         CASE WHEN p_lat IS NOT NULL AND p_lng IS NOT NULL
              THEN ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography END AS pt,
         (SELECT array_agg(c.id) FROM categories c
           WHERE c.id = ANY(p_category_ids) OR c.parent_id = ANY(p_category_ids)) AS cats,
         (SELECT favorite_retailers FROM app_users WHERE id = p_favorites_of)   AS favs
),
base AS (
  SELECT o.*, r.name_ar AS r_name, r.type AS r_type, pr.nq, pr.d, pr.pt,
         CASE WHEN pr.nq <> '' THEN word_similarity(pr.nq, o.search_text) ELSE 0 END AS trg_sim,
         CASE WHEN p_embedding IS NOT NULL AND o.embedding IS NOT NULL
              THEN 1 - (o.embedding <=> p_embedding) ELSE 0 END            AS vec_sim
  FROM offers o
  JOIN retailers r ON r.id = o.retailer_id AND r.is_active
  CROSS JOIN params pr
  WHERE o.status = 'live'
    -- الصلاحية
    AND o.valid_to >= pr.d
    AND (o.valid_from <= pr.d OR (p_include_upcoming AND o.valid_from <= pr.d + 3))
    AND (p_ends_within_days IS NULL OR o.valid_to <= pr.d + p_ends_within_days)
    -- النص (حرفي أو تقريبي أو دلالي)
    AND (pr.nq = '' OR o.search_text LIKE '%' || pr.nq || '%'
         OR pr.nq <% o.search_text                       -- تشابه كلمات (يتحمّل الأخطاء: دره/ذرة، حفاظات/حفاضات)
         OR (p_embedding IS NOT NULL AND o.embedding <=> p_embedding < 0.55))
    AND (p_brand IS NULL OR normalize_ar(o.brand) = normalize_ar(p_brand)
         OR similarity(normalize_ar(o.brand), normalize_ar(p_brand)) > 0.5)
    AND (p_category_ids IS NULL OR o.category_id = ANY(pr.cats))
    AND (p_retailer_ids IS NULL OR o.retailer_id = ANY(p_retailer_ids))
    AND (p_retailer_types IS NULL OR r.type = ANY(p_retailer_types))
    AND (p_favorites_of IS NULL OR o.retailer_id = ANY(coalesce(pr.favs, '{}')))
    -- المكان
    AND (p_governorate_id IS NULL OR o.governorate_ids = '{}' OR p_governorate_id = ANY(o.governorate_ids))
    -- الخصم والسعر والنوع
    AND (p_discount_min IS NULL OR o.discount_pct >= p_discount_min)
    AND (p_discount_max IS NULL OR o.discount_pct <= p_discount_max)
    AND (p_price_min IS NULL OR o.price_jod >= p_price_min)
    AND (p_price_max IS NULL OR o.price_jod <= p_price_max)
    AND (p_offer_types IS NULL OR o.offer_type = ANY(p_offer_types))
    AND (p_channels IS NULL OR o.channels && p_channels)
    AND (p_campaign IS NULL OR o.campaign_id = (SELECT id FROM campaigns WHERE slug = p_campaign))
    -- الحجم (±15%)
    AND (p_size_value IS NULL OR (
          o.size_value * unit_to_base(o.size_unit)
            BETWEEN p_size_value * unit_to_base(coalesce(p_size_unit, o.size_unit)) * 0.85
                AND p_size_value * unit_to_base(coalesce(p_size_unit, o.size_unit)) * 1.15))
    AND (p_has_coupon IS NULL OR p_has_coupon = EXISTS (
          SELECT 1 FROM coupons c WHERE c.retailer_id = o.retailer_id AND c.is_active
             AND (c.valid_to IS NULL OR c.valid_to >= pr.d)))
    AND (p_min_rating IS NULL OR (SELECT avg(rating) FROM offer_ratings x WHERE x.offer_id = o.id) >= p_min_rating)
),
located AS (
  SELECT b.*, nb.branch_id, nb.dist_km, nb.open_any
  FROM base b
  LEFT JOIN LATERAL (
    SELECT br.id AS branch_id,
           CASE WHEN b.pt IS NOT NULL AND br.geo IS NOT NULL
                THEN round((ST_Distance(br.geo, b.pt) / 1000)::numeric, 2) END AS dist_km,
           bool_or(is_open_at(br.opening_hours)) OVER () AS open_any
    FROM branches br
    WHERE br.retailer_id = b.retailer_id AND br.is_active
      AND (b.branch_ids = '{}' OR br.id = ANY(b.branch_ids))
      AND (p_governorate_id IS NULL OR br.governorate_id = p_governorate_id)
      AND (p_open_now IS NULL OR NOT p_open_now OR is_open_at(br.opening_hours))
    ORDER BY dist_km NULLS LAST
    LIMIT 1
  ) nb ON true
  WHERE (p_radius_km IS NULL OR b.pt IS NULL OR nb.dist_km <= p_radius_km)
    AND (p_open_now IS NULL OR NOT p_open_now OR nb.branch_id IS NOT NULL)
)
SELECT l.id, l.product_name_ar, l.product_name_en, l.brand, l.size_label,
       l.price_jod, l.old_price_jod, l.discount_pct, l.unit_price, l.unit_label,
       l.offer_type, l.offer_note, l.retailer_id, l.r_name,
       l.valid_from, l.valid_to, (l.valid_to - l.d)::int,
       l.channels, l.image_url, l.online_url, l.is_sponsored,
       l.dist_km, l.branch_id,
       round((0.55 * l.trg_sim + 0.45 * l.vec_sim)::numeric, 4),
       count(*) OVER ()
FROM located l
ORDER BY
  CASE WHEN p_sort = 'price_asc'   THEN l.price_jod   END ASC  NULLS LAST,
  CASE WHEN p_sort = 'price_desc'  THEN l.price_jod   END DESC NULLS LAST,
  CASE WHEN p_sort = 'unit_price'  THEN l.unit_price  END ASC  NULLS LAST,
  CASE WHEN p_sort = 'discount'    THEN l.discount_pct END DESC NULLS LAST,
  CASE WHEN p_sort = 'ending_soon' THEN l.valid_to    END ASC  NULLS LAST,
  CASE WHEN p_sort = 'newest'      THEN l.created_at  END DESC NULLS LAST,
  CASE WHEN p_sort = 'popularity'  THEN l.trend_score END DESC NULLS LAST,
  CASE WHEN p_sort = 'distance'    THEN l.dist_km     END ASC  NULLS LAST,
  CASE WHEN p_sort = 'alpha'       THEN l.product_name_ar END ASC,
  (0.55 * l.trg_sim + 0.45 * l.vec_sim) DESC,
  l.discount_pct DESC NULLS LAST,
  l.id
LIMIT greatest(1, least(coalesce(p_limit, 10), 50)) OFFSET greatest(0, coalesce(p_offset, 0))
$$;

-- compare_prices: نفس المنتج عند كل متجر (أرخص عرض لكل متجر، مرتب بسعر الوحدة)
CREATE OR REPLACE FUNCTION compare_prices(
  p_query           text,
  p_embedding       vector   DEFAULT NULL,
  p_governorate_id  smallint DEFAULT NULL,
  p_size_value      numeric  DEFAULT NULL,
  p_size_unit       text     DEFAULT NULL,
  p_brand           text     DEFAULT NULL
)
RETURNS TABLE (retailer_id bigint, retailer_name text, offer_id bigint, product_name_ar text,
               size_label text, price_jod numeric, old_price_jod numeric, unit_price numeric,
               unit_label text, valid_to date, rank_in_compare int)
LANGUAGE sql STABLE AS $$
  SELECT x.retailer_id, x.retailer_name, x.offer_id, x.product_name_ar, x.size_label,
         x.price_jod, x.old_price_jod, x.unit_price, x.unit_label, x.valid_to,
         (row_number() OVER (ORDER BY x.unit_price NULLS LAST, x.price_jod))::int
  FROM (
    SELECT DISTINCT ON (s.retailer_id) s.*
    FROM search_offers(p_query => p_query, p_embedding => p_embedding, p_brand => p_brand,
                       p_governorate_id => p_governorate_id, p_size_value => p_size_value,
                       p_size_unit => p_size_unit, p_sort => 'unit_price', p_limit => 50) s
    ORDER BY s.retailer_id, s.unit_price NULLS LAST, s.price_jod
  ) x
  ORDER BY 11
$$;

-- price_check: هل السعر الحالي حقيقي؟ (أدنى/متوسط سعر خلال 90 يومًا)
CREATE OR REPLACE FUNCTION price_check(p_offer_id bigint)
RETURNS TABLE (current_price numeric, min_90d numeric, avg_90d numeric, max_90d numeric,
               is_lowest_90d boolean, observations int)
LANGUAGE sql STABLE AS $$
  SELECT o.price_jod, min(h.price_jod), round(avg(h.price_jod), 3), max(h.price_jod),
         o.price_jod <= coalesce(min(h.price_jod), o.price_jod), count(h.*)::int
  FROM offers o
  LEFT JOIN price_history h ON h.product_id = o.product_id
                           AND h.observed_on >= amman_today() - 90
  WHERE o.id = p_offer_id
  GROUP BY o.price_jod
$$;

-- match_product: مطابقة عرض مستخرج مع الكتالوج (WF2)
CREATE OR REPLACE FUNCTION match_product(p_name text, p_brand text DEFAULT NULL,
                                         p_embedding vector DEFAULT NULL, p_min_score numeric DEFAULT 0.6)
RETURNS TABLE (product_id bigint, score numeric)
LANGUAGE sql STABLE AS $$
  SELECT p.id,
         round((0.5 * similarity(p.search_text, normalize_ar(coalesce(p_brand, '') || ' ' || p_name))
              + 0.5 * CASE WHEN p_embedding IS NOT NULL AND p.embedding IS NOT NULL
                           THEN 1 - (p.embedding <=> p_embedding) ELSE 0 END)::numeric, 4) AS sc
  FROM products p
  WHERE p.search_text % normalize_ar(p_name)
     OR (p_embedding IS NOT NULL AND p.embedding <=> p_embedding < 0.3)
  ORDER BY sc DESC
  LIMIT 1
$$;

-- matching_alerts: التنبيهات التي يطابقها عرض جديد (WF5 / WF9)
CREATE OR REPLACE FUNCTION matching_alerts(p_offer_id bigint)
RETURNS TABLE (alert_id bigint, user_id uuid)
LANGUAGE sql STABLE AS $$
  SELECT a.id, a.user_id
  FROM offers o
  JOIN alerts a ON a.is_active
  WHERE o.id = p_offer_id AND o.status = 'live'
    AND (a.product_id IS NULL OR a.product_id = o.product_id)
    AND (a.brand IS NULL OR normalize_ar(a.brand) = normalize_ar(o.brand))
    AND (a.category_id IS NULL OR a.category_id = o.category_id)
    AND (a.query_norm IS NULL OR o.search_text LIKE '%' || a.query_norm || '%'
         OR word_similarity(a.query_norm, o.search_text) >= 0.5)
    AND (a.retailer_ids = '{}' OR o.retailer_id = ANY(a.retailer_ids))
    AND (a.governorate_id IS NULL OR o.governorate_ids = '{}' OR a.governorate_id = ANY(o.governorate_ids))
    AND (a.target_price_jod IS NULL OR o.price_jod <= a.target_price_jod)
    AND (a.min_discount_pct IS NULL OR o.discount_pct >= a.min_discount_pct)
    AND NOT EXISTS (SELECT 1 FROM alert_notifications n WHERE n.alert_id = a.id AND n.offer_id = o.id)
$$;

-- =====================================================================
-- 10.5 سلّة العيلة الأسبوعية + عدّاد التوفير
-- =====================================================================
-- المستخدم يحفظ سلته مرة واحدة (كتابة / صوت / صورة ورقة المقاضي).
-- كل أسبوع: run_basket_week() تحسب أرخص توزيع على 1–3 متاجر، والوكيل يرسلها صباح الخميس.
-- basket_to_list() تحوّلها لقائمة تسوق وتسجّل التوفير في savings_ledger (عدّاد التوفير).

CREATE TABLE IF NOT EXISTS family_baskets (
  id                  bigserial PRIMARY KEY,
  user_id             uuid NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
  name                text NOT NULL DEFAULT 'سلّة العيلة',
  household_size      smallint CHECK (household_size BETWEEN 1 AND 20),
  weekly_budget_jod   numeric(10,3),
  governorate_id      smallint REFERENCES governorates(id),     -- NULL = محافظة المستخدم
  max_stores          smallint NOT NULL DEFAULT 2 CHECK (max_stores BETWEEN 1 AND 3),
  store_penalty_jod   numeric(6,3) NOT NULL DEFAULT 0.750,      -- "كلفة المشوار": متجر إضافي يجب أن يوفّر أكثر منها
  excluded_retailers  bigint[] NOT NULL DEFAULT '{}',
  send_dow            smallint NOT NULL DEFAULT 4 CHECK (send_dow BETWEEN 0 AND 6),  -- 0=الأحد … 4=الخميس
  send_hour           smallint NOT NULL DEFAULT 9 CHECK (send_hour BETWEEN 0 AND 23),
  created_from        text CHECK (created_from IN ('text','voice','image','list')),
  is_active           boolean NOT NULL DEFAULT true,
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS family_baskets_user_idx ON family_baskets (user_id) WHERE is_active;
CREATE INDEX IF NOT EXISTS family_baskets_send_idx ON family_baskets (send_dow, send_hour) WHERE is_active;
DROP TRIGGER IF EXISTS family_baskets_updated ON family_baskets;
CREATE TRIGGER family_baskets_updated BEFORE UPDATE ON family_baskets FOR EACH ROW EXECUTE FUNCTION trg_set_updated_at();

CREATE TABLE IF NOT EXISTS basket_items (
  id              bigserial PRIMARY KEY,
  basket_id       bigint NOT NULL REFERENCES family_baskets(id) ON DELETE CASCADE,
  query           text NOT NULL,                 -- عام: "زيت ذرة" (أي ماركة)
  query_norm      text GENERATED ALWAYS AS (normalize_ar(query)) STORED,
  brand           text,                          -- NULL = أي ماركة (الأفضل للتوفير)
  category_id     int REFERENCES categories(id),
  size_value      numeric(10,3),                 -- NULL = أي حجم (يُقارن بسعر الوحدة)
  size_unit       text CHECK (size_unit IN ('g','kg','ml','l','pcs','pack')),
  qty             numeric(8,2) NOT NULL DEFAULT 1 CHECK (qty > 0),
  frequency       text NOT NULL DEFAULT 'weekly' CHECK (frequency IN ('weekly','biweekly','monthly')),
  last_bought_on  date,
  sort_order      int NOT NULL DEFAULT 0,
  is_active       boolean NOT NULL DEFAULT true,
  created_at      timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS basket_items_basket_idx ON basket_items (basket_id) WHERE is_active;

-- حساب كل أسبوع (سطر واحد لكل سلة لكل أسبوع)
CREATE TABLE IF NOT EXISTS basket_runs (
  id                       bigserial PRIMARY KEY,
  basket_id                bigint NOT NULL REFERENCES family_baskets(id) ON DELETE CASCADE,
  week_start               date NOT NULL,
  computed_at              timestamptz NOT NULL DEFAULT now(),
  plan                     jsonb NOT NULL,                 -- مخرج optimize_items كاملًا
  stores_used              smallint,
  items_total              int,
  items_found              int,
  best_total_jod           numeric(10,3),
  regular_total_jod        numeric(10,3),                  -- نفس الأصناف بالسعر العادي
  single_store_total_jod   numeric(10,3),
  savings_vs_regular_jod   numeric(10,3),
  savings_vs_single_jod    numeric(10,3),
  message_id               uuid REFERENCES messages(id) ON DELETE SET NULL,
  sent_at                  timestamptz,
  opened_at                timestamptz,
  converted_at             timestamptz,
  list_id                  bigint REFERENCES shopping_lists(id) ON DELETE SET NULL,
  UNIQUE (basket_id, week_start)
);
CREATE INDEX IF NOT EXISTS basket_runs_week_idx ON basket_runs (week_start);

-- عدّاد التوفير
CREATE TABLE IF NOT EXISTS savings_ledger (
  id             bigserial PRIMARY KEY,
  user_id        uuid NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
  basket_run_id  bigint REFERENCES basket_runs(id) ON DELETE SET NULL,
  week_start     date NOT NULL,
  savings_jod    numeric(10,3) NOT NULL CHECK (savings_jod >= 0),
  basis          text NOT NULL DEFAULT 'regular_price' CHECK (basis IN ('regular_price','single_store','receipt')),
  source         text NOT NULL DEFAULT 'basket' CHECK (source IN ('basket','list','receipt')),
  confirmed      boolean NOT NULL DEFAULT false,      -- true بعد تأكيد الشراء (إيصال أو تأشير القائمة)
  created_at     timestamptz NOT NULL DEFAULT now(),
  UNIQUE (basket_run_id)
);
CREATE INDEX IF NOT EXISTS savings_ledger_user_idx ON savings_ledger (user_id, week_start DESC);

-- الأصناف المستحقة هذا الأسبوع حسب تكرارها
CREATE OR REPLACE FUNCTION basket_items_due(p_basket_id bigint, p_on date DEFAULT amman_today())
RETURNS SETOF basket_items LANGUAGE sql STABLE AS $$
  SELECT * FROM basket_items i
  WHERE i.basket_id = p_basket_id AND i.is_active
    AND (i.frequency = 'weekly' OR i.last_bought_on IS NULL
         OR (i.frequency = 'biweekly' AND i.last_bought_on <= p_on - 13)
         OR (i.frequency = 'monthly'  AND i.last_bought_on <= p_on - 27))
  ORDER BY i.sort_order, i.id
$$;

-- optimize_items: قلب الميزة. يأخذ أي قائمة أصناف (JSON) ويرجع أرخص خطة على ≤ p_max_stores متاجر.
-- هي نفسها أداة الوكيل optimize_basket لقائمة يكتبها المستخدم في المحادثة.
-- p_items مثال:
--   [{"query":"زيت ذرة","size_value":1.5,"size_unit":"l","qty":1},
--    {"query":"رز","brand":"الضحى","qty":2}]
-- الخوارزمية: لكل صنف أرخص عرض في كل متجر، ثم تجربة كل تركيبات المتاجر (1..3)،
-- واختيار الأكثر تغطية للأصناف ثم الأقل (مجموعًا + كلفة مشوار لكل متجر إضافي).
CREATE OR REPLACE FUNCTION optimize_items(
  p_items            jsonb,
  p_governorate_id   smallint DEFAULT NULL,
  p_max_stores       int      DEFAULT 2,
  p_store_penalty    numeric  DEFAULT 0.75,
  p_excluded         bigint[] DEFAULT '{}'
)
RETURNS jsonb LANGUAGE sql STABLE AS $$
WITH items AS (
  SELECT coalesce((e->>'item_id')::bigint, n)              AS item_id,
         e->>'query'                                       AS query,
         nullif(e->>'brand', '')                           AS brand,
         (e->>'size_value')::numeric                       AS size_value,
         nullif(e->>'size_unit', '')                       AS size_unit,
         coalesce((e->>'qty')::numeric, 1)                 AS qty
  FROM jsonb_array_elements(p_items) WITH ORDINALITY AS t(e, n)
  WHERE coalesce(e->>'query', '') <> ''
),
cand AS (       -- أرخص عرض لكل (صنف × متجر)
  SELECT DISTINCT ON (i.item_id, s.retailer_id)
         i.item_id, i.query, i.qty, s.retailer_id, s.retailer_name, s.offer_id, s.product_name_ar,
         s.size_label, s.price_jod, coalesce(s.old_price_jod, s.price_jod) AS regular_price,
         s.unit_price, s.unit_label, s.valid_to,
         round(s.price_jod * i.qty, 3)                                    AS line,
         round(coalesce(s.old_price_jod, s.price_jod) * i.qty, 3)         AS regular_line
  FROM items i
  CROSS JOIN LATERAL search_offers(
      p_query => i.query, p_brand => i.brand, p_governorate_id => p_governorate_id,
      p_size_value => i.size_value, p_size_unit => i.size_unit,
      p_sort => 'unit_price', p_limit => 50) s
  WHERE NOT (s.retailer_id = ANY(coalesce(p_excluded, '{}')))
  ORDER BY i.item_id, s.retailer_id,
           CASE WHEN i.size_value IS NULL THEN s.unit_price END NULLS LAST,  -- بلا حجم: الأرخص للوحدة
           s.price_jod
),
rs AS (SELECT DISTINCT retailer_id AS r FROM cand),
combos AS (
  SELECT ARRAY[a.r] AS c FROM rs a
  UNION ALL SELECT ARRAY[a.r, b.r] FROM rs a JOIN rs b ON a.r < b.r WHERE p_max_stores >= 2
  UNION ALL SELECT ARRAY[a.r, b.r, c.r] FROM rs a JOIN rs b ON a.r < b.r JOIN rs c ON b.r < c.r WHERE p_max_stores >= 3
),
eval AS (
  SELECT co.c, count(*) AS covered, sum(x.best) AS total,
         sum(x.best) + (cardinality(co.c) - 1) * p_store_penalty AS score
  FROM combos co
  CROSS JOIN LATERAL (SELECT item_id, min(line) AS best FROM cand
                      WHERE retailer_id = ANY(co.c) GROUP BY item_id) x
  GROUP BY co.c
),
best AS   (SELECT c, covered, total FROM eval ORDER BY covered DESC, score, cardinality(c) LIMIT 1),
single AS (SELECT c, covered, total FROM eval WHERE cardinality(c) = 1 ORDER BY covered DESC, total LIMIT 1),
assign AS (     -- كل صنف لأرخص متجر ضمن التركيبة المختارة
  SELECT DISTINCT ON (cd.item_id) cd.*
  FROM cand cd, best b
  WHERE cd.retailer_id = ANY(b.c)
  ORDER BY cd.item_id, cd.line, cd.retailer_id
),
per_store AS (
  SELECT retailer_id, min(retailer_name) AS retailer_name, sum(line) AS subtotal,
         jsonb_agg(jsonb_build_object(
           'item_id', item_id, 'query', query, 'qty', qty, 'offer_id', offer_id,
           'product', product_name_ar, 'size', size_label, 'price_jod', price_jod,
           'regular_price_jod', regular_price, 'line_jod', line,
           'unit_price', unit_price, 'unit_label', unit_label, 'valid_to', valid_to)
           ORDER BY item_id) AS items
  FROM assign GROUP BY retailer_id
)
SELECT jsonb_build_object(
  'items_total',            (SELECT count(*) FROM items),
  'items_found',            (SELECT count(*) FROM assign),
  'stores',                 coalesce((SELECT jsonb_agg(jsonb_build_object(
                               'retailer_id', retailer_id, 'retailer_name', retailer_name,
                               'subtotal_jod', subtotal, 'items', items) ORDER BY subtotal DESC)
                             FROM per_store), '[]'::jsonb),
  'stores_used',            (SELECT count(*) FROM per_store),
  'total_jod',              (SELECT sum(line) FROM assign),
  'regular_total_jod',      (SELECT sum(regular_line) FROM assign),
  'savings_vs_regular_jod', (SELECT sum(regular_line) - sum(line) FROM assign),
  'single_store',           (SELECT jsonb_build_object(
                               'retailer_id', s.c[1],
                               'retailer_name', (SELECT retailer_name FROM cand WHERE retailer_id = s.c[1] LIMIT 1),
                               'items_found', s.covered, 'total_jod', s.total)
                             FROM single s),
  -- المقارنة مع متجر واحد عادلة فقط عندما يغطي نفس عدد الأصناف
  'savings_vs_single_jod',  (SELECT CASE WHEN s.covered = b.covered THEN s.total - b.total END
                             FROM single s, best b),
  'missing',                coalesce((SELECT jsonb_agg(jsonb_build_object('item_id', i.item_id, 'query', i.query))
                             FROM items i WHERE i.item_id NOT IN (SELECT item_id FROM assign)), '[]'::jsonb),
  'computed_for',           amman_today()
)
$$;

-- optimize_basket: نفس الحساب لسلة محفوظة (الأصناف المستحقة فقط افتراضيًا)
CREATE OR REPLACE FUNCTION optimize_basket(p_basket_id bigint, p_max_stores int DEFAULT NULL,
                                           p_only_due boolean DEFAULT true)
RETURNS jsonb LANGUAGE sql STABLE AS $$
  SELECT optimize_items(
           coalesce((SELECT jsonb_agg(jsonb_build_object(
                        'item_id', i.id, 'query', i.query, 'brand', i.brand,
                        'size_value', i.size_value, 'size_unit', i.size_unit, 'qty', i.qty)
                        ORDER BY i.sort_order, i.id)
                     FROM basket_items i
                     WHERE i.basket_id = b.id AND i.is_active
                       AND (NOT p_only_due OR i.id IN (SELECT id FROM basket_items_due(b.id)))), '[]'::jsonb),
           coalesce(b.governorate_id, u.governorate_id),
           coalesce(p_max_stores, b.max_stores),
           b.store_penalty_jod,
           b.excluded_retailers)
  FROM family_baskets b JOIN app_users u ON u.id = b.user_id
  WHERE b.id = p_basket_id
$$;

-- run_basket_week: يحسب ويحفظ خطة الأسبوع (يستدعيه WF16 ليلة الأربعاء لكل سلة نشطة)
CREATE OR REPLACE FUNCTION run_basket_week(p_basket_id bigint)
RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE
  v_plan jsonb := optimize_basket(p_basket_id);
  v_week date  := date_trunc('week', amman_today())::date;
  v_id   bigint;
BEGIN
  INSERT INTO basket_runs (basket_id, week_start, plan, stores_used, items_total, items_found,
                           best_total_jod, regular_total_jod, single_store_total_jod,
                           savings_vs_regular_jod, savings_vs_single_jod)
  VALUES (p_basket_id, v_week, v_plan,
          (v_plan->>'stores_used')::smallint, (v_plan->>'items_total')::int, (v_plan->>'items_found')::int,
          (v_plan->>'total_jod')::numeric, (v_plan->>'regular_total_jod')::numeric,
          (v_plan->'single_store'->>'total_jod')::numeric,
          (v_plan->>'savings_vs_regular_jod')::numeric, (v_plan->>'savings_vs_single_jod')::numeric)
  ON CONFLICT (basket_id, week_start) DO UPDATE
     SET plan = EXCLUDED.plan, computed_at = now(), stores_used = EXCLUDED.stores_used,
         items_total = EXCLUDED.items_total, items_found = EXCLUDED.items_found,
         best_total_jod = EXCLUDED.best_total_jod, regular_total_jod = EXCLUDED.regular_total_jod,
         single_store_total_jod = EXCLUDED.single_store_total_jod,
         savings_vs_regular_jod = EXCLUDED.savings_vs_regular_jod,
         savings_vs_single_jod = EXCLUDED.savings_vs_single_jod
     WHERE basket_runs.converted_at IS NULL          -- لا نغيّر خطة حوّلها المستخدم لقائمة
  RETURNING id INTO v_id;
  IF v_id IS NULL THEN
    SELECT id INTO v_id FROM basket_runs WHERE basket_id = p_basket_id AND week_start = v_week;
  END IF;
  RETURN v_id;
END $$;

-- baskets_due_now: السلال التي حان موعد إرسالها (يستدعيه WF16 كل ساعة)
CREATE OR REPLACE FUNCTION baskets_due_now()
RETURNS TABLE (basket_id bigint, user_id uuid, run_id bigint) LANGUAGE sql STABLE AS $$
  SELECT b.id, b.user_id, r.id
  FROM family_baskets b
  LEFT JOIN basket_runs r ON r.basket_id = b.id AND r.week_start = date_trunc('week', amman_today())::date
  WHERE b.is_active
    AND b.send_dow = extract(dow FROM amman_now())::int
    AND b.send_hour <= extract(hour FROM amman_now())::int
    AND (r.id IS NULL OR r.sent_at IS NULL)
$$;

-- basket_to_list: "حوّلها لقائمة" → تُضاف لقائمة التسوق الافتراضية ويُسجّل التوفير
CREATE OR REPLACE FUNCTION basket_to_list(p_run_id bigint)
RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE
  v_user uuid; v_basket bigint; v_plan jsonb; v_list bigint; v_week date; v_done timestamptz;
BEGIN
  SELECT b.user_id, r.basket_id, r.plan, r.week_start, r.converted_at
    INTO v_user, v_basket, v_plan, v_week, v_done
    FROM basket_runs r JOIN family_baskets b ON b.id = r.basket_id WHERE r.id = p_run_id;
  IF v_user IS NULL THEN RAISE EXCEPTION 'basket run % not found', p_run_id; END IF;
  IF v_done IS NOT NULL THEN RETURN (SELECT list_id FROM basket_runs WHERE id = p_run_id); END IF;

  INSERT INTO shopping_lists (user_id, is_default) VALUES (v_user, true)
  ON CONFLICT (user_id) WHERE is_default DO NOTHING;
  SELECT id INTO v_list FROM shopping_lists WHERE user_id = v_user AND is_default;

  INSERT INTO list_items (list_id, offer_id, qty, price_at_add, saved_at_add, added_from)
  SELECT v_list, (it->>'offer_id')::bigint, (it->>'qty')::numeric, (it->>'price_jod')::numeric,
         (it->>'regular_price_jod')::numeric - (it->>'price_jod')::numeric, 'chat'
  FROM jsonb_array_elements(v_plan->'stores') st, jsonb_array_elements(st->'items') it;

  UPDATE basket_items SET last_bought_on = amman_today()
   WHERE basket_id = v_basket
     AND id IN (SELECT (it->>'item_id')::bigint
                FROM jsonb_array_elements(v_plan->'stores') st, jsonb_array_elements(st->'items') it);

  UPDATE basket_runs SET converted_at = now(), list_id = v_list WHERE id = p_run_id;

  INSERT INTO savings_ledger (user_id, basket_run_id, week_start, savings_jod, basis, source)
  VALUES (v_user, p_run_id, v_week, greatest(coalesce((v_plan->>'savings_vs_regular_jod')::numeric, 0), 0),
          'regular_price', 'basket')
  ON CONFLICT (basket_run_id) DO NOTHING;

  RETURN v_list;
END $$;

-- عدّاد التوفير للمستخدم (للرسالة الأسبوعية وللواجهة)
CREATE OR REPLACE VIEW v_user_savings AS
SELECT u.id AS user_id,
       coalesce(sum(l.savings_jod), 0)                                                   AS total_saved_jod,
       coalesce(sum(l.savings_jod) FILTER (WHERE l.week_start > amman_today() - 30), 0)  AS saved_30d_jod,
       coalesce(sum(l.savings_jod) FILTER (WHERE l.confirmed), 0)                        AS confirmed_saved_jod,
       count(l.id)                                                                       AS weeks_used,
       min(l.week_start)                                                                 AS since
FROM app_users u LEFT JOIN savings_ledger l ON l.user_id = u.id
GROUP BY u.id;

-- لوحة الشركة: أداء السلة أسبوعيًا
CREATE OR REPLACE VIEW v_basket_kpis_weekly AS
SELECT r.week_start,
       count(*)                                                                  AS baskets_computed,
       count(*) FILTER (WHERE r.sent_at IS NOT NULL)                             AS sent,
       round(100.0 * count(*) FILTER (WHERE r.opened_at IS NOT NULL)
             / nullif(count(*) FILTER (WHERE r.sent_at IS NOT NULL), 0), 1)       AS open_rate_pct,
       round(100.0 * count(*) FILTER (WHERE r.converted_at IS NOT NULL)
             / nullif(count(*) FILTER (WHERE r.sent_at IS NOT NULL), 0), 1)       AS convert_rate_pct,
       round(avg(r.savings_vs_regular_jod), 3)                                   AS avg_savings_jod,
       round(avg(r.savings_vs_single_jod), 3)                                    AS avg_savings_vs_single_jod,
       round(100.0 * sum(r.items_found) / nullif(sum(r.items_total), 0), 1)      AS coverage_pct,
       round(avg(r.stores_used), 2)                                              AS avg_stores
FROM basket_runs r
GROUP BY r.week_start
ORDER BY r.week_start DESC;

-- الطلب المخطط (أثمن بيانات للعلامات التجارية): ماذا تنوي العائلات شراءه، حسب المحافظة — مجمّع بلا هوية
CREATE OR REPLACE VIEW v_planned_demand AS
SELECT g.name_ar AS governorate, i.query_norm AS item, coalesce(lower(i.brand), 'أي ماركة') AS brand,
       count(DISTINCT b.id) AS baskets, round(sum(i.qty), 1) AS weekly_qty
FROM basket_items i
JOIN family_baskets b ON b.id = i.basket_id AND b.is_active
JOIN app_users u ON u.id = b.user_id
LEFT JOIN governorates g ON g.id = coalesce(b.governorate_id, u.governorate_id)
WHERE i.is_active
GROUP BY 1, 2, 3
HAVING count(DISTINCT b.id) >= 5          -- لا يُعرض أي بند يخص أقل من 5 عائلات (حماية الخصوصية)
ORDER BY baskets DESC;

-- =====================================================================
-- 11. الصيانة (يستدعيها WF3 يوميًا)
-- =====================================================================
CREATE OR REPLACE FUNCTION expire_offers()
RETURNS TABLE (offers_expired int, flyers_expired int)
LANGUAGE plpgsql AS $$
DECLARE a int; b int;
BEGIN
  UPDATE offers SET status = 'expired'
   WHERE status IN ('live','paused') AND valid_to < amman_today();
  GET DIAGNOSTICS a = ROW_COUNT;
  UPDATE flyers SET status = 'expired'
   WHERE status IN ('live','paused','review') AND valid_to < amman_today();
  GET DIAGNOSTICS b = ROW_COUNT;
  RETURN QUERY SELECT a, b;
END $$;

-- trend_score من تفاعل آخر 48 ساعة (ظهور 1 · نقرة 3 · إضافة للقائمة 5 · اتجاهات 6)
CREATE OR REPLACE FUNCTION refresh_trending()
RETURNS int LANGUAGE plpgsql AS $$
DECLARE n int;
BEGIN
  WITH s AS (
    SELECT offer_id,
           count(*) FILTER (WHERE event_name = 'offer_impression')  AS imp,
           count(*) FILTER (WHERE event_name = 'offer_click')       AS clk,
           count(*) FILTER (WHERE event_name = 'list_add')          AS sav,
           count(*) FILTER (WHERE event_name = 'directions_click')  AS dir
    FROM events
    WHERE created_at > now() - interval '48 hours' AND offer_id IS NOT NULL
    GROUP BY offer_id
  )
  UPDATE offers o
     SET trend_score = s.imp + 3 * s.clk + 5 * s.sav + 6 * s.dir,
         views = o.views + 0                                  -- العدادات الكلية تُحدّث في WF12
    FROM s
   WHERE o.id = s.offer_id AND o.status = 'live';
  GET DIAGNOSTICS n = ROW_COUNT;
  UPDATE offers SET trend_score = 0
   WHERE status = 'live' AND trend_score > 0
     AND id NOT IN (SELECT DISTINCT offer_id FROM events
                     WHERE created_at > now() - interval '48 hours' AND offer_id IS NOT NULL);
  RETURN n;
END $$;

-- إنشاء أقسام شهرية لجدول events (شغّلها شهريًا من n8n، وتُشغّل مرة الآن)
CREATE OR REPLACE FUNCTION ensure_event_partitions(p_months_ahead int DEFAULT 3)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE
  m  date := date_trunc('month', now())::date;
  i  int;
  nm text;
BEGIN
  FOR i IN 0..p_months_ahead LOOP
    nm := 'events_' || to_char(m + (i || ' month')::interval, 'YYYY_MM');
    IF to_regclass(nm) IS NULL THEN
      EXECUTE format('CREATE TABLE %I PARTITION OF events FOR VALUES FROM (%L) TO (%L)',
                     nm, m + (i || ' month')::interval, m + ((i + 1) || ' month')::interval);
    END IF;
  END LOOP;
END $$;

-- =====================================================================
-- 12. لوحات Metabase
-- =====================================================================

-- 12.1 مؤشرات يومية (Materialized: تُحدّث ليلًا عبر refresh_analytics)
DROP MATERIALIZED VIEW IF EXISTS mv_daily_metrics CASCADE;
CREATE MATERIALIZED VIEW mv_daily_metrics AS
SELECT (e.created_at AT TIME ZONE 'Asia/Amman')::date                                   AS day,
       count(DISTINCT coalesce(e.user_id::text, e.anon_id))                              AS visitors,
       count(DISTINCT e.user_id) FILTER (WHERE e.event_name = 'message_sent')            AS active_users,
       count(DISTINCT e.session_id)                                                      AS sessions,
       count(*) FILTER (WHERE e.event_name = 'signup')                                   AS signups,
       count(*) FILTER (WHERE e.event_name = 'message_sent')                             AS messages,
       count(*) FILTER (WHERE e.event_name = 'search_performed')                         AS searches,
       count(*) FILTER (WHERE e.event_name = 'zero_results')                             AS zero_results,
       count(*) FILTER (WHERE e.event_name = 'offer_impression')                         AS impressions,
       count(*) FILTER (WHERE e.event_name = 'offer_click')                              AS clicks,
       count(*) FILTER (WHERE e.event_name = 'list_add')                                 AS list_adds,
       count(*) FILTER (WHERE e.event_name = 'directions_click')                         AS directions,
       count(*) FILTER (WHERE e.event_name = 'feedback' AND (e.props->>'value') = '1')   AS thumbs_up,
       count(*) FILTER (WHERE e.event_name = 'feedback' AND (e.props->>'value') = '-1')  AS thumbs_down
FROM events e
GROUP BY 1;
CREATE UNIQUE INDEX mv_daily_metrics_day ON mv_daily_metrics (day);

-- 12.2 الطلب اليومي حسب المحافظة × المتجر × الفئة
DROP MATERIALIZED VIEW IF EXISTS mv_daily_demand CASCADE;
CREATE MATERIALIZED VIEW mv_daily_demand AS
SELECT (e.created_at AT TIME ZONE 'Asia/Amman')::date AS day,
       coalesce(e.governorate_id, 0)                  AS governorate_id,   -- 0 = غير معروف
       coalesce(e.retailer_id, 0)                     AS retailer_id,
       coalesce(e.category_id, 0)                     AS category_id,
       count(*) FILTER (WHERE e.event_name = 'search_performed') AS searches,
       count(*) FILTER (WHERE e.event_name = 'offer_click')      AS clicks,
       count(*) FILTER (WHERE e.event_name = 'list_add')         AS list_adds,
       count(DISTINCT coalesce(e.user_id::text, e.anon_id))      AS users
FROM events e
WHERE e.event_name IN ('search_performed','offer_click','list_add')
GROUP BY 1, 2, 3, 4;
CREATE UNIQUE INDEX mv_daily_demand_pk ON mv_daily_demand (day, governorate_id, retailer_id, category_id);

-- 12.3 الذكاء: تكلفة وزمن يومي
DROP MATERIALIZED VIEW IF EXISTS mv_daily_ai CASCADE;
CREATE MATERIALIZED VIEW mv_daily_ai AS
SELECT (created_at AT TIME ZONE 'Asia/Amman')::date AS day,
       count(*)                                     AS turns,
       count(DISTINCT conversation_id)              AS conversations,
       round(avg(latency_ms))                       AS avg_latency_ms,
       percentile_disc(0.95) WITHIN GROUP (ORDER BY latency_ms) AS p95_latency_ms,
       sum(tokens_in)                               AS tokens_in,
       sum(tokens_out)                              AS tokens_out,
       round(sum(cost_usd), 4)                      AS cost_usd,
       count(*) FILTER (WHERE error IS NOT NULL)    AS errors
FROM agent_turns
GROUP BY 1;
CREATE UNIQUE INDEX mv_daily_ai_day ON mv_daily_ai (day);

CREATE OR REPLACE FUNCTION refresh_analytics()
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  REFRESH MATERIALIZED VIEW CONCURRENTLY mv_daily_metrics;
  REFRESH MATERIALIZED VIEW CONCURRENTLY mv_daily_demand;
  REFRESH MATERIALIZED VIEW CONCURRENTLY mv_daily_ai;
  -- العدادات الكلية على العروض
  UPDATE offers o SET views = s.v, clicks = s.c, saves = s.s
  FROM (SELECT offer_id,
               count(*) FILTER (WHERE event_name = 'offer_impression') v,
               count(*) FILTER (WHERE event_name = 'offer_click')      c,
               count(*) FILTER (WHERE event_name = 'list_add')         s
        FROM events WHERE offer_id IS NOT NULL GROUP BY offer_id) s
  WHERE o.id = s.offer_id;
END $$;

-- 12.4 أكثر المتاجر طلبًا (30 يومًا)
CREATE OR REPLACE VIEW v_top_retailers_30d AS
SELECT r.id AS retailer_id, r.name_ar, r.type,
       sum(d.searches) AS searches, sum(d.clicks) AS clicks, sum(d.list_adds) AS list_adds,
       sum(d.searches) + 3 * sum(d.clicks) + 5 * sum(d.list_adds) AS demand_score
FROM mv_daily_demand d JOIN retailers r ON r.id = d.retailer_id
WHERE d.day > amman_today() - 30
GROUP BY r.id, r.name_ar, r.type
ORDER BY demand_score DESC;

-- 12.5 أكثر المنتجات والعلامات طلبًا (30 يومًا) من نص البحث الفعلي
CREATE OR REPLACE VIEW v_top_queries_30d AS
SELECT normalize_ar(e.props->>'query')        AS query,
       count(*)                               AS searches,
       count(DISTINCT coalesce(e.user_id::text, e.anon_id)) AS users,
       round(avg((e.props->>'results_count')::numeric), 1) AS avg_results
FROM events e
WHERE e.event_name = 'search_performed' AND e.created_at > now() - interval '30 days'
  AND coalesce(e.props->>'query', '') <> ''
GROUP BY 1 ORDER BY searches DESC;

CREATE OR REPLACE VIEW v_top_brands_30d AS
SELECT lower(e.props->>'brand') AS brand, count(*) AS searches
FROM events e
WHERE e.event_name = 'search_performed' AND e.created_at > now() - interval '30 days'
  AND e.props ? 'brand'
GROUP BY 1 ORDER BY searches DESC;

CREATE OR REPLACE VIEW v_top_offers_30d AS
SELECT o.id AS offer_id, o.product_name_ar, r.name_ar AS retailer, o.price_jod, o.discount_pct,
       count(*) FILTER (WHERE e.event_name = 'offer_click') AS clicks,
       count(*) FILTER (WHERE e.event_name = 'list_add')    AS list_adds
FROM events e JOIN offers o ON o.id = e.offer_id JOIN retailers r ON r.id = o.retailer_id
WHERE e.created_at > now() - interval '30 days' AND e.event_name IN ('offer_click','list_add')
GROUP BY o.id, o.product_name_ar, r.name_ar, o.price_jod, o.discount_pct
ORDER BY list_adds DESC, clicks DESC;

-- 12.6 المحافظات: المستخدمون والطلب وفجوة التغطية
CREATE OR REPLACE VIEW v_governorates_30d AS
SELECT g.id, g.name_ar,
       (SELECT count(*) FROM app_users u WHERE u.governorate_id = g.id AND u.deleted_at IS NULL) AS users_total,
       coalesce(sum(d.searches), 0)  AS searches_30d,
       coalesce(sum(d.list_adds), 0) AS list_adds_30d,
       (SELECT count(*) FROM offers o WHERE o.status = 'live'
           AND (o.governorate_ids = '{}' OR g.id = ANY(o.governorate_ids)))                AS live_offers,
       round(coalesce(sum(d.searches), 0)::numeric /
             nullif((SELECT count(*) FROM offers o WHERE o.status = 'live'
                       AND (o.governorate_ids = '{}' OR g.id = ANY(o.governorate_ids))), 0), 2) AS searches_per_offer
FROM governorates g
LEFT JOIN mv_daily_demand d ON d.governorate_id = g.id AND d.day > amman_today() - 30
GROUP BY g.id, g.name_ar
ORDER BY searches_30d DESC;

-- 12.7 الطلب غير الملبّى (بحث بلا نتائج) — 7 أيام
CREATE OR REPLACE VIEW v_zero_results_7d AS
SELECT g.name_ar AS governorate, normalize_ar(e.props->>'query') AS query, count(*) AS n
FROM events e LEFT JOIN governorates g ON g.id = e.governorate_id
WHERE e.event_name = 'zero_results' AND e.created_at > now() - interval '7 days'
GROUP BY 1, 2 ORDER BY n DESC;

-- 12.8 قمع التحويل (30 يومًا) ونسب الدخول
CREATE OR REPLACE VIEW v_funnel_30d AS
WITH u AS (
  SELECT coalesce(user_id::text, anon_id) AS who,
         bool_or(event_name IN ('visit','session_start'))  AS visited,
         bool_or(event_name = 'message_sent')              AS messaged,
         bool_or(event_name = 'search_performed')          AS searched,
         bool_or(event_name = 'offer_click')               AS clicked,
         bool_or(event_name = 'list_add')                  AS saved,
         bool_or(event_name IN ('directions_click','store_contact')) AS went_to_store,
         bool_or(event_name = 'signup')                    AS signed_up
  FROM events WHERE created_at > now() - interval '30 days'
  GROUP BY 1
)
SELECT step, n, round(100.0 * n / nullif(first_value(n) OVER (ORDER BY ord), 0), 1) AS pct_of_visitors
FROM (
  SELECT 1 AS ord, 'زار الموقع'          AS step, count(*) FILTER (WHERE visited)       AS n FROM u UNION ALL
  SELECT 2, 'أرسل رسالة',                          count(*) FILTER (WHERE messaged)      FROM u UNION ALL
  SELECT 3, 'بحث عن عرض',                          count(*) FILTER (WHERE searched)      FROM u UNION ALL
  SELECT 4, 'نقر على عرض',                         count(*) FILTER (WHERE clicked)       FROM u UNION ALL
  SELECT 5, 'أضاف للقائمة',                         count(*) FILTER (WHERE saved)         FROM u UNION ALL
  SELECT 6, 'اتجاهات / تواصل مع المتجر',           count(*) FILTER (WHERE went_to_store) FROM u UNION ALL
  SELECT 7, 'أنشأ حسابًا',                          count(*) FILTER (WHERE signed_up)     FROM u
) s
ORDER BY ord;

-- 12.9 الاحتفاظ الأسبوعي (D1 / D7 / D30) لكل فوج تسجيل
CREATE OR REPLACE VIEW v_retention_weekly AS
WITH f AS (
  SELECT user_id, min((created_at AT TIME ZONE 'Asia/Amman')::date) AS d0
  FROM events WHERE user_id IS NOT NULL GROUP BY user_id
),
a AS (
  SELECT DISTINCT user_id, (created_at AT TIME ZONE 'Asia/Amman')::date AS d
  FROM events WHERE user_id IS NOT NULL
)
SELECT date_trunc('week', f.d0)::date AS cohort_week,
       count(DISTINCT f.user_id)      AS users,
       round(100.0 * count(DISTINCT a.user_id) FILTER (WHERE a.d = f.d0 + 1) / count(DISTINCT f.user_id), 1) AS d1_pct,
       round(100.0 * count(DISTINCT a.user_id) FILTER (WHERE a.d BETWEEN f.d0 + 7 AND f.d0 + 13) / count(DISTINCT f.user_id), 1) AS d7_pct,
       round(100.0 * count(DISTINCT a.user_id) FILTER (WHERE a.d BETWEEN f.d0 + 30 AND f.d0 + 36) / count(DISTINCT f.user_id), 1) AS d30_pct
FROM f LEFT JOIN a ON a.user_id = f.user_id
GROUP BY 1 ORDER BY 1 DESC;

-- 12.10 خريطة حرارية للدخول (يوم × ساعة، 30 يومًا)
CREATE OR REPLACE VIEW v_usage_heatmap_30d AS
SELECT extract(isodow FROM created_at AT TIME ZONE 'Asia/Amman')::int AS iso_dow,   -- 1=الاثنين … 7=الأحد
       extract(hour   FROM created_at AT TIME ZONE 'Asia/Amman')::int AS hour,
       count(DISTINCT session_id) AS sessions
FROM events
WHERE event_name IN ('session_start','visit') AND created_at > now() - interval '30 days'
GROUP BY 1, 2;

-- 12.11 الأجهزة ومصادر الزيارات
CREATE OR REPLACE VIEW v_sources_30d AS
SELECT coalesce(device::text, 'unknown') AS device, coalesce(utm_source, 'direct') AS source,
       count(DISTINCT session_id) AS sessions,
       count(DISTINCT coalesce(user_id::text, anon_id)) AS visitors
FROM events
WHERE event_name IN ('session_start','visit') AND created_at > now() - interval '30 days'
GROUP BY 1, 2 ORDER BY sessions DESC;

-- 12.12 المستخدمون وبياناتهم (صفحة "المستخدمون" — للمدير والدعم فقط)
CREATE OR REPLACE VIEW v_users_overview AS
SELECT u.id, u.display_name, u.email, u.phone, u.is_guest, u.signup_method,
       g.name_ar AS governorate, a.name_ar AS area, u.language, u.first_device, u.utm_source,
       u.created_at, u.signed_up_at, u.last_seen_at,
       (SELECT count(DISTINCT session_id) FROM events e WHERE e.user_id = u.id)                          AS sessions,
       (SELECT count(*) FROM events e WHERE e.user_id = u.id AND e.event_name = 'message_sent')          AS messages,
       (SELECT count(*) FROM conversations c WHERE c.user_id = u.id)                                     AS conversations,
       (SELECT count(*) FROM alerts al WHERE al.user_id = u.id AND al.is_active)                         AS active_alerts,
       (SELECT coalesce(sum(li.saved_at_add * li.qty), 0) FROM list_items li
          JOIN shopping_lists sl ON sl.id = li.list_id WHERE sl.user_id = u.id)                          AS est_savings_jod,
       (SELECT array_agg(r.name_ar) FROM retailers r WHERE r.id = ANY(u.favorite_retailers))             AS favorite_retailers,
       CASE WHEN coalesce(u.last_seen_at, u.created_at) > now() - interval '7 days'  THEN 'نشط'
            WHEN coalesce(u.last_seen_at, u.created_at) > now() - interval '30 days' THEN 'في خطر'
            ELSE 'منقطع' END                                                                              AS segment
FROM app_users u
LEFT JOIN governorates g ON g.id = u.governorate_id
LEFT JOIN areas a        ON a.id = u.area_id
WHERE u.deleted_at IS NULL;

-- 12.13 جودة الذكاء: توزيع النوايا ونسبة الرضا
CREATE OR REPLACE VIEW v_ai_intents_30d AS
SELECT coalesce(intent, 'unknown') AS intent, count(*) AS turns,
       round(avg(latency_ms)) AS avg_latency_ms, round(sum(cost_usd), 4) AS cost_usd,
       round(100.0 * count(*) FILTER (WHERE results_count = 0) / nullif(count(*), 0), 1) AS zero_result_pct,
       round(100.0 * count(*) FILTER (WHERE error IS NOT NULL) / nullif(count(*), 0), 1) AS error_pct
FROM agent_turns WHERE created_at > now() - interval '30 days'
GROUP BY 1 ORDER BY turns DESC;

CREATE OR REPLACE VIEW v_negative_feedback AS
SELECT m.feedback_at, m.feedback_reason, m.content AS assistant_reply,
       (SELECT q.content FROM messages q WHERE q.conversation_id = m.conversation_id
          AND q.role = 'user' AND q.created_at < m.created_at ORDER BY q.created_at DESC LIMIT 1) AS user_question,
       m.conversation_id
FROM messages m WHERE m.feedback = -1
ORDER BY m.feedback_at DESC;

-- 12.14 المحتوى والتجار
CREATE OR REPLACE VIEW v_retailer_content AS
SELECT r.id, r.name_ar, r.is_partner, r.plan,
       count(DISTINCT f.id) FILTER (WHERE f.status = 'live')                        AS live_flyers,
       count(o.id)          FILTER (WHERE o.status = 'live')                        AS live_offers,
       max(f.created_at)                                                            AS last_upload,
       round(avg(extract(epoch FROM (f.published_at - f.created_at)) / 60)
             FILTER (WHERE f.published_at IS NOT NULL))                             AS avg_minutes_to_publish,
       round(100.0 * sum(f.offers_edited) / nullif(sum(f.offers_extracted), 0), 1)  AS edit_rate_pct,
       (SELECT count(*) FROM offer_reports rp JOIN offers ox ON ox.id = rp.offer_id
         WHERE ox.retailer_id = r.id AND rp.status = 'open')                        AS open_reports,
       CASE WHEN max(f.valid_to) < amman_today() + 2 THEN true ELSE false END       AS needs_new_flyer
FROM retailers r
LEFT JOIN flyers f ON f.retailer_id = r.id
LEFT JOIN offers o ON o.flyer_id = f.id
GROUP BY r.id, r.name_ar, r.is_partner, r.plan;

-- 12.15 إحصائيات التاجر (لبوابة التاجر — تُفلتر بـ retailer_id)
CREATE OR REPLACE VIEW v_retailer_stats_30d AS
SELECT e.retailer_id,
       count(*) FILTER (WHERE e.event_name = 'offer_impression') AS impressions,
       count(*) FILTER (WHERE e.event_name = 'offer_click')      AS clicks,
       count(*) FILTER (WHERE e.event_name = 'list_add')         AS list_adds,
       count(*) FILTER (WHERE e.event_name = 'directions_click') AS directions,
       count(*) FILTER (WHERE e.event_name = 'store_contact')    AS contacts,
       round(100.0 * count(*) FILTER (WHERE e.event_name = 'offer_click')
             / nullif(count(*) FILTER (WHERE e.event_name = 'offer_impression'), 0), 2) AS ctr_pct
FROM events e
WHERE e.retailer_id IS NOT NULL AND e.created_at > now() - interval '30 days'
GROUP BY e.retailer_id;

-- 12.16 الإيرادات
CREATE OR REPLACE VIEW v_revenue_monthly AS
WITH inv AS (
  SELECT date_trunc('month', issued_on)::date AS month,
         sum(amount_jod) FILTER (WHERE status = 'paid')   AS paid_jod,
         sum(amount_jod) FILTER (WHERE status = 'unpaid') AS unpaid_jod,
         count(DISTINCT retailer_id)                      AS paying_retailers
  FROM invoices GROUP BY 1
),
ai AS (
  SELECT date_trunc('month', created_at AT TIME ZONE 'Asia/Amman')::date AS month,
         round(sum(cost_usd), 2) AS ai_cost_usd
  FROM agent_turns GROUP BY 1
)
SELECT coalesce(inv.month, ai.month) AS month,
       coalesce(inv.paid_jod, 0)   AS paid_jod,
       coalesce(inv.unpaid_jod, 0) AS unpaid_jod,
       coalesce(inv.paying_retailers, 0) AS paying_retailers,
       coalesce(ai.ai_cost_usd, 0) AS ai_cost_usd
FROM inv FULL JOIN ai ON ai.month = inv.month
ORDER BY 1 DESC;

-- =====================================================================
-- 13. الصلاحيات و RLS
-- =====================================================================
GRANT USAGE ON SCHEMA public TO amman_app, amman_readonly, amman_merchant;

-- n8n: قراءة وكتابة على كل شيء
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO amman_app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO amman_app;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO amman_app;

-- Metabase: قراءة فقط
GRANT SELECT ON ALL TABLES IN SCHEMA public TO amman_readonly;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO amman_readonly;

-- بوابة التاجر: جداوله فقط، ومقيّد بمتجره عبر:  SET app.retailer_id = '<id>';
GRANT SELECT ON retailers, branches, categories, campaigns, governorates, areas TO amman_merchant;
GRANT SELECT, INSERT, UPDATE ON flyers, flyer_pages, offers, branches TO amman_merchant;
GRANT SELECT ON v_retailer_stats_30d, subscriptions, invoices, sponsored_slots TO amman_merchant;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO amman_merchant;

ALTER TABLE flyers   ENABLE ROW LEVEL SECURITY;
ALTER TABLE offers   ENABLE ROW LEVEL SECURITY;
ALTER TABLE branches ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS flyers_app       ON flyers;
DROP POLICY IF EXISTS flyers_merchant  ON flyers;
DROP POLICY IF EXISTS offers_app       ON offers;
DROP POLICY IF EXISTS offers_merchant  ON offers;
DROP POLICY IF EXISTS branches_app     ON branches;
DROP POLICY IF EXISTS branches_merchant ON branches;

CREATE POLICY flyers_app   ON flyers   TO amman_app, amman_readonly USING (true) WITH CHECK (true);
CREATE POLICY offers_app   ON offers   TO amman_app, amman_readonly USING (true) WITH CHECK (true);
CREATE POLICY branches_app ON branches TO amman_app, amman_readonly USING (true) WITH CHECK (true);

CREATE POLICY flyers_merchant ON flyers TO amman_merchant
  USING      (retailer_id = nullif(current_setting('app.retailer_id', true), '')::bigint)
  WITH CHECK (retailer_id = nullif(current_setting('app.retailer_id', true), '')::bigint);
CREATE POLICY offers_merchant ON offers TO amman_merchant
  USING      (retailer_id = nullif(current_setting('app.retailer_id', true), '')::bigint)
  WITH CHECK (retailer_id = nullif(current_setting('app.retailer_id', true), '')::bigint);
CREATE POLICY branches_merchant ON branches TO amman_merchant
  USING      (retailer_id = nullif(current_setting('app.retailer_id', true), '')::bigint)
  WITH CHECK (retailer_id = nullif(current_setting('app.retailer_id', true), '')::bigint);

-- الجداول المستقبلية تأخذ نفس الصلاحيات
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO amman_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO amman_readonly;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO amman_app;

-- =====================================================================
-- 14. بيانات أولية
-- =====================================================================
INSERT INTO governorates (id, code, name_ar, name_en, aliases, center) VALUES
 (1,  'AM', 'عمّان',   'Amman',   '{عمان,amman,العاصمة}', ST_SetSRID(ST_MakePoint(35.9106, 31.9539), 4326)::geography),
 (2,  'IR', 'إربد',    'Irbid',   '{اربد,irbid}',          ST_SetSRID(ST_MakePoint(35.8500, 32.5556), 4326)::geography),
 (3,  'AZ', 'الزرقاء', 'Zarqa',   '{الزرقا,زرقاء,zarqa}',  ST_SetSRID(ST_MakePoint(36.0880, 32.0728), 4326)::geography),
 (4,  'BA', 'البلقاء', 'Balqa',   '{السلط,بلقاء,salt,balqa}', ST_SetSRID(ST_MakePoint(35.7275, 32.0392), 4326)::geography),
 (5,  'MA', 'المفرق',  'Mafraq',  '{مفرق,mafraq}',          ST_SetSRID(ST_MakePoint(36.2081, 32.3429), 4326)::geography),
 (6,  'KA', 'الكرك',   'Karak',   '{كرك,karak}',            ST_SetSRID(ST_MakePoint(35.7048, 31.1853), 4326)::geography),
 (7,  'JA', 'جرش',     'Jerash',  '{jerash,jarash}',        ST_SetSRID(ST_MakePoint(35.8998, 32.2803), 4326)::geography),
 (8,  'AJ', 'عجلون',   'Ajloun',  '{ajloun,ajlun}',         ST_SetSRID(ST_MakePoint(35.7517, 32.3326), 4326)::geography),
 (9,  'MD', 'مادبا',   'Madaba',  '{مأدبا,madaba}',         ST_SetSRID(ST_MakePoint(35.7939, 31.7160), 4326)::geography),
 (10, 'AQ', 'العقبة',  'Aqaba',   '{عقبة,aqaba}',           ST_SetSRID(ST_MakePoint(35.0063, 29.5321), 4326)::geography),
 (11, 'AT', 'الطفيلة', 'Tafilah', '{طفيلة,tafila,tafilah}', ST_SetSRID(ST_MakePoint(35.6045, 30.8375), 4326)::geography),
 (12, 'MN', 'معان',    'Maan',    '{maan,ma''an}',          ST_SetSRID(ST_MakePoint(35.7340, 30.1962), 4326)::geography)
ON CONFLICT (id) DO NOTHING;

INSERT INTO areas (governorate_id, name_ar, name_en, aliases) VALUES
 (1, 'خلدا',         'Khalda',        '{khalda}'),
 (1, 'الصويفية',     'Sweifieh',      '{صويفيه,sweifieh,swefieh}'),
 (1, 'الشميساني',    'Shmeisani',     '{شميساني,shmeisani}'),
 (1, 'عبدون',        'Abdoun',        '{abdoun}'),
 (1, 'طبربور',       'Tabarbour',     '{tabarbour}'),
 (1, 'مرج الحمام',   'Marj Al Hamam', '{marj al hamam}'),
 (1, 'الجبيهة',      'Jubeiha',       '{جبيهة,jubeiha}'),
 (1, 'تلاع العلي',   'Tla Al Ali',    '{تلاع علي,tla al ali}'),
 (1, 'ماركا',        'Marka',         '{marka}'),
 (1, 'وادي السير',   'Wadi Al Seer',  '{wadi al seer}'),
 (1, 'سحاب',         'Sahab',         '{sahab}'),
 (1, 'الدوار السابع','7th Circle',    '{السابع,7th circle}')
ON CONFLICT (governorate_id, name_ar) DO NOTHING;

INSERT INTO categories (slug, name_ar, name_en, synonyms, sort_order) VALUES
 ('grocery',      'بقالة ومواد غذائية', 'Grocery',            '{مواد تموينية,مؤونة,رز,سكر,زيت}', 1),
 ('dairy',        'ألبان وأجبان وبيض',  'Dairy & Eggs',       '{حليب,لبنة,جبنة,لبن,بيض}',        2),
 ('fresh',        'خضار وفواكه',        'Fruits & Vegetables','{خضرة,فواكه,خضار}',               3),
 ('meat',         'لحوم ودواجن وأسماك', 'Meat, Poultry & Fish','{لحمة,دجاج,جاج,سمك}',            4),
 ('frozen',       'مجمدات',             'Frozen',             '{فريزر,مثلجات}',                  5),
 ('bakery',       'مخبوزات',            'Bakery',             '{خبز,كعك}',                       6),
 ('beverages',    'مشروبات',            'Beverages',          '{عصير,مي,مياه,قهوة,شاي}',         7),
 ('snacks',       'سناكات وحلويات',     'Snacks & Sweets',    '{شيبس,شوكولاتة,بسكويت}',          8),
 ('cleaning',     'منظفات',             'Cleaning',           '{تنظيف,مسحوق,كلور,جلي}',          9),
 ('personal_care','العناية الشخصية',    'Personal Care',      '{شامبو,صابون,معجون}',             10),
 ('health_beauty','صحة وجمال',          'Health & Beauty',    '{مكياج,عطور,فيتامينات}',          11),
 ('baby',         'الأم والطفل',        'Baby & Mom',         '{حفاضات,بامبرز,حليب أطفال}',      12),
 ('electronics',  'إلكترونيات',         'Electronics',        '{موبايل,تلفزيون,شاشة,لابتوب}',    13),
 ('appliances',   'أجهزة منزلية',       'Home Appliances',    '{غسالة,ثلاجة,مكيف,فرن}',          14),
 ('home_garden',  'البيت والحديقة',     'Home & Garden',      '{أدوات منزلية,مطبخ,أثاث}',        15),
 ('fashion',      'أزياء',              'Fashion',            '{ملابس,أحذية}',                   16),
 ('toys',         'ألعاب',              'Toys',               '{العاب}',                         17),
 ('pets',         'حيوانات أليفة',      'Pets',               '{أكل قطط,أكل كلاب}',              18),
 ('stationery',   'قرطاسية',            'Stationery',         '{مدرسة,دفاتر,أقلام}',             19)
ON CONFLICT (slug) DO NOTHING;

INSERT INTO campaigns (slug, name_ar, name_en) VALUES
 ('ramadan',        'رمضان',            'Ramadan'),
 ('eid_fitr',       'عيد الفطر',        'Eid Al-Fitr'),
 ('eid_adha',       'عيد الأضحى',       'Eid Al-Adha'),
 ('back_to_school', 'العودة للمدارس',   'Back to School'),
 ('white_friday',   'الجمعة البيضاء',   'White Friday')
ON CONFLICT (slug) DO NOTHING;

-- متاجر مبدئية (راجع الأنواع والأسماء قبل الإطلاق)
INSERT INTO retailers (slug, name_ar, name_en, aliases, type) VALUES
 ('ctown',        'سي تاون',                        'C Town',          '{سيتاون,سي تاون,ctown,c-town}',    'supermarket'),
 ('safeway',      'سيفوي',                          'Safeway',         '{سيف وي,safeway}',                 'supermarket'),
 ('cozmo',        'كوزمو',                          'Cozmo',           '{كوزمو,cozmo}',                    'hypermarket'),
 ('hypermax',     'هايبرماكس',                      'Hypermax',        '{هايبر ماكس,كارفور,carrefour}',    'hypermarket'),
 ('sameh_mall',   'سامح مول',                       'Sameh Mall',      '{سامح,sameh}',                     'hypermarket'),
 ('yaser_mall',   'ياسر مول',                       'Yaser Mall',      '{ياسر,yaser}',                     'supermarket'),
 ('military_coop','المؤسسة الاستهلاكية العسكرية',  'Military Consumer Corporation', '{العسكرية,المؤسسة العسكرية}', 'consumer_coop'),
 ('civil_coop',   'المؤسسة الاستهلاكية المدنية',   'Civil Consumer Corporation',    '{المدنية,المؤسسة المدنية}',   'consumer_coop'),
 ('leaders',      'ليدرز سنتر',                     'Leaders Center',  '{ليدرز,leaders}',                  'electronics'),
 ('ikea',         'ايكيا',                          'IKEA',            '{ايكيا,إيكيا,ikea}',               'furniture')
ON CONFLICT (slug) DO NOTHING;

-- أقسام events للشهر الحالي و3 أشهر قادمة
SELECT ensure_event_partitions(3);

COMMIT;

-- بعد التشغيل:
--   ALTER ROLE amman_app LOGIN PASSWORD '...';  (واستخدمه في Credentials داخل n8n)
--   ALTER ROLE amman_readonly LOGIN PASSWORD '...';  (لـ Metabase)
-- جدولة في n8n:
--   يوميًا 00:05  → SELECT * FROM expire_offers();
--   كل ساعة       → SELECT refresh_trending();
--   يوميًا 02:00  → SELECT refresh_analytics();
--   شهريًا         → SELECT ensure_event_partitions(3);
--   الأربعاء 23:00 → SELECT run_basket_week(id) FROM family_baskets WHERE is_active;
--   كل ساعة       → SELECT * FROM baskets_due_now();   (ثم إرسال رسالة السلة وتعيين sent_at)
