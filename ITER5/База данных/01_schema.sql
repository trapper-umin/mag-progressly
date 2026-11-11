-- PostgreSQL 17. Применять к пустой учебной БД.
BEGIN;
CREATE SCHEMA progressly;
SET search_path TO progressly, public;

CREATE TABLE app_user (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  email text UNIQUE CHECK (email = lower(btrim(email)) AND email <> ''),
  telegram_id text UNIQUE CHECK (telegram_id ~ '^[0-9]+$'),
  registered_at timestamptz NOT NULL DEFAULT now(),
  CHECK (email IS NOT NULL OR telegram_id IS NOT NULL)
);
CREATE TABLE user_session (
  token_hash text PRIMARY KEY CHECK (token_hash ~ '^[0-9a-f]{64}$'),
  user_id uuid NOT NULL REFERENCES app_user ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL,
  revoked_at timestamptz,
  CHECK (expires_at > created_at),
  CHECK (revoked_at >= created_at)
);
CREATE INDEX user_session_owner_idx ON user_session(user_id);

CREATE TABLE tracker (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES app_user ON DELETE CASCADE,
  name text NOT NULL CHECK (btrim(name) <> ''),
  periodicity text NOT NULL CHECK (periodicity IN ('DAILY','WEEKLY','MONTHLY')),
  active boolean NOT NULL DEFAULT true,
  UNIQUE (id, user_id),
  UNIQUE (id, periodicity)
);
CREATE INDEX tracker_owner_idx ON tracker(user_id);

CREATE TABLE tracker_field (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tracker_id uuid NOT NULL REFERENCES tracker ON DELETE CASCADE,
  name text NOT NULL CHECK (btrim(name) <> ''),
  kind text NOT NULL CHECK (kind IN ('NUMBER','SCALE','FLAG','TEXT','CHOICE','TIME')),
  required boolean NOT NULL DEFAULT false,
  config jsonb NOT NULL DEFAULT '{}',
  CHECK (jsonb_typeof(config) = 'object'),
  CHECK (kind <> 'CHOICE' OR
         (jsonb_typeof(config->'options') = 'array') IS TRUE),
  UNIQUE (tracker_id, name),
  UNIQUE (tracker_id, id, kind)
);
CREATE TABLE entry (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tracker_id uuid NOT NULL,
  periodicity text NOT NULL,
  entry_date date NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tracker_id, entry_date),
  UNIQUE (tracker_id, id),
  FOREIGN KEY (tracker_id, periodicity) REFERENCES tracker(id, periodicity) ON DELETE CASCADE,
  CHECK (periodicity = 'DAILY'
         OR (periodicity = 'WEEKLY' AND extract(isodow FROM entry_date) = 1)
         OR (periodicity = 'MONTHLY' AND extract(day FROM entry_date) = 1))
);
CREATE TABLE field_value (
  entry_id uuid NOT NULL,
  field_id uuid NOT NULL,
  tracker_id uuid NOT NULL,
  kind text NOT NULL,
  number_value numeric,
  flag_value boolean,
  text_value text,
  time_value time,
  PRIMARY KEY (entry_id, field_id),
  FOREIGN KEY (tracker_id, entry_id) REFERENCES entry(tracker_id, id) ON DELETE CASCADE,
  FOREIGN KEY (tracker_id, field_id, kind) REFERENCES tracker_field(tracker_id, id, kind)
    ON DELETE CASCADE,
  CHECK (num_nonnulls(number_value, flag_value, text_value, time_value) = 1),
  CHECK (CASE kind
    WHEN 'NUMBER' THEN number_value IS NOT NULL
    WHEN 'SCALE' THEN number_value IS NOT NULL AND number_value BETWEEN 1 AND 10
                      AND number_value = trunc(number_value)
    WHEN 'FLAG' THEN flag_value IS NOT NULL
    WHEN 'TEXT' THEN text_value IS NOT NULL
    WHEN 'CHOICE' THEN text_value IS NOT NULL
    WHEN 'TIME' THEN time_value IS NOT NULL ELSE false END),
  CHECK (number_value NOT IN ('NaN'::numeric,'Infinity'::numeric,'-Infinity'::numeric))
);
CREATE INDEX field_value_history_idx ON field_value(tracker_id, field_id, kind);

CREATE TABLE streak (
  tracker_id uuid PRIMARY KEY REFERENCES tracker ON DELETE CASCADE,
  current_length integer NOT NULL CHECK (current_length >= 0),
  best_length integer NOT NULL CHECK (best_length >= current_length),
  updated_on date NOT NULL
);
CREATE TABLE goal_group (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES app_user ON DELETE CASCADE,
  title text NOT NULL,
  UNIQUE (user_id, id)
);
CREATE TABLE goal (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  group_id uuid NOT NULL,
  tracker_id uuid NOT NULL,
  field_id uuid NOT NULL,
  kind text NOT NULL CHECK (kind IN ('NUMBER','SCALE')),
  title text NOT NULL,
  target_value numeric NOT NULL,
  starts_on date NOT NULL,
  ends_before date NOT NULL CHECK (ends_before > starts_on),
  status text NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE','ACHIEVED','FAILED')),
  FOREIGN KEY (user_id, group_id) REFERENCES goal_group(user_id, id) ON DELETE CASCADE,
  FOREIGN KEY (tracker_id, user_id) REFERENCES tracker(id, user_id) ON DELETE CASCADE,
  FOREIGN KEY (tracker_id, field_id, kind) REFERENCES tracker_field(tracker_id, id, kind)
    ON DELETE CASCADE
);
CREATE INDEX goal_group_owner_idx ON goal(user_id, group_id);
CREATE INDEX goal_field_idx ON goal(tracker_id, field_id, kind);

CREATE TABLE subscription (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL UNIQUE REFERENCES app_user ON DELETE CASCADE,
  tariff text NOT NULL DEFAULT 'FREE' CHECK (tariff IN ('FREE','FREE_PRO','PRO')),
  starts_on date NOT NULL,
  ends_before date,
  auto_renew boolean NOT NULL DEFAULT false,
  CHECK ((tariff = 'FREE' AND ends_before IS NULL AND NOT auto_renew)
      OR (tariff <> 'FREE' AND ends_before IS NOT NULL AND ends_before > starts_on))
);
CREATE TABLE payment (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  subscription_id uuid NOT NULL REFERENCES subscription ON DELETE CASCADE,
  provider_payment_id text NOT NULL UNIQUE,
  requested_tariff text NOT NULL CHECK (requested_tariff IN ('PRO')),
  amount numeric(12,2) NOT NULL CHECK (amount > 0 AND amount <> 'NaN'::numeric),
  currency char(3) NOT NULL DEFAULT 'RUB' CHECK (currency = 'RUB'),
  created_at timestamptz NOT NULL DEFAULT now(),
  status text NOT NULL DEFAULT 'CREATED' CHECK (status IN ('CREATED','PAID','DECLINED'))
);
CREATE INDEX payment_subscription_idx ON payment(subscription_id);

CREATE TABLE ai_summary (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES app_user ON DELETE CASCADE,
  starts_on date NOT NULL,
  ends_before date NOT NULL CHECK (ends_before > starts_on),
  summary_text text NOT NULL,
  insights text[] NOT NULL DEFAULT '{}',
  advice text[] NOT NULL DEFAULT '{}',
  created_at timestamptz NOT NULL DEFAULT now(),
  read_at timestamptz,
  CHECK (read_at >= created_at),
  UNIQUE (user_id, starts_on, ends_before)
);

-- Статус вычисляется, чтобы он не расходился со значениями полей.
CREATE VIEW entry_status AS
SELECT e.id, e.tracker_id, e.entry_date,
       CASE WHEN NOT EXISTS (SELECT 1 FROM field_value v WHERE v.entry_id = e.id)
            THEN 'EMPTY'
            WHEN EXISTS (
              SELECT 1 FROM tracker_field f
              WHERE f.tracker_id = e.tracker_id AND f.required
                AND NOT EXISTS (SELECT 1 FROM field_value v
                                WHERE v.entry_id = e.id AND v.field_id = f.id))
            THEN 'PARTIAL' ELSE 'COMPLETE' END AS status
FROM entry e;

COMMIT;
