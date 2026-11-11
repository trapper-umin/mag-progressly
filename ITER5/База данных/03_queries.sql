\pset pager off
SET search_path TO progressly, public;
SET TIME ZONE 'UTC';

\echo 'UC-01 | История записей и заполненность'
SELECT s.entry_date, s.status
FROM entry_status s
JOIN tracker t ON t.id = s.tracker_id
WHERE t.user_id = '00000000-0000-4000-8000-000000000001'
  AND t.id = '10000000-0000-4000-8000-000000000001'
  AND s.entry_date >= DATE '2026-10-05' AND s.entry_date < DATE '2026-10-12'
ORDER BY s.entry_date;

\echo 'UC-02 | Агрегаты для AI-сводки по полям за неделю'
SELECT f.name, count(*) AS observations, round(avg(v.number_value),2) AS mean
FROM tracker t
JOIN entry e ON e.tracker_id = t.id
JOIN field_value v ON v.entry_id = e.id
JOIN tracker_field f ON f.id = v.field_id
WHERE t.user_id = '00000000-0000-4000-8000-000000000001'
  AND e.entry_date >= DATE '2026-10-05' AND e.entry_date < DATE '2026-10-12'
  AND v.kind IN ('NUMBER','SCALE')
GROUP BY f.id, f.name ORDER BY f.id;

\echo 'UC-02 | Готовая AI-сводка при действующем PRO'
SELECT a.starts_on, a.ends_before, a.summary_text, a.read_at IS NOT NULL AS is_read
FROM ai_summary a JOIN subscription s USING (user_id)
WHERE a.user_id = '00000000-0000-4000-8000-000000000001'
  AND (a.starts_on, a.ends_before) = (DATE '2026-10-05', DATE '2026-10-08')
  AND s.tariff = 'PRO' AND s.starts_on <= DATE '2026-10-08'
  AND s.ends_before > DATE '2026-10-08';

\echo 'UC-03 | Проверка токена на фиксированный момент UTC'
SELECT u.email, s.expires_at
FROM user_session s JOIN app_user u ON u.id = s.user_id
WHERE s.token_hash = repeat('a',64)
  AND s.revoked_at IS NULL
  AND TIMESTAMPTZ '2026-10-08 10:00+00' >= s.created_at
  AND TIMESTAMPTZ '2026-10-08 10:00+00' < s.expires_at;

\echo 'UC-04 | Тарифы на 08.10 и история платежей'
SELECT u.email, u.telegram_id,
       CASE WHEN DATE '2026-10-08' >= s.starts_on
                  AND (s.ends_before IS NULL OR DATE '2026-10-08' < s.ends_before)
            THEN s.tariff ELSE 'FREE' END AS effective_tariff,
       p.provider_payment_id, p.status
FROM app_user u
LEFT JOIN subscription s ON s.user_id = u.id
LEFT JOIN payment p ON p.subscription_id = s.id
ORDER BY u.id, p.created_at;
