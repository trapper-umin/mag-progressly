\pset pager off
\echo 'Проверки выполняются в транзакции и не меняют демонстрационные данные.'
BEGIN;
SET search_path TO progressly, public;

DO $$
BEGIN
  IF (SELECT array_agg(status ORDER BY entry_date) FROM entry_status)
       IS DISTINCT FROM ARRAY['COMPLETE','COMPLETE','PARTIAL','EMPTY'] THEN
    RAISE EXCEPTION 'Неверные статусы записей';
  END IF;
  IF (SELECT avg(v.number_value) FROM field_value v JOIN tracker_field f ON f.id=v.field_id
      WHERE f.name='Сон, ч') IS DISTINCT FROM 7.5 THEN
    RAISE EXCEPTION 'Неверная аналитика сна';
  END IF;
  IF (SELECT array_agg(left(token_hash, 1)) FROM user_session
      WHERE TIMESTAMPTZ '2026-10-08 10:00+00' >= created_at
        AND TIMESTAMPTZ '2026-10-08 10:00+00' < expires_at AND revoked_at IS NULL)
       IS DISTINCT FROM ARRAY['a'] THEN
    RAISE EXCEPTION 'Неверный результат проверки TTL';
  END IF;
  IF (SELECT count(*) FROM ai_summary a JOIN subscription s USING (user_id)
      WHERE s.tariff = 'PRO' AND DATE '2026-10-08' >= s.starts_on
        AND DATE '2026-10-08' < s.ends_before) <> 1 THEN
    RAISE EXCEPTION 'Неверный доступ к сводке';
  END IF;
  RAISE NOTICE 'OK: статусы, среднее 7,5 ч, срок сессии, доступ PRO';
END $$;

DO $$
BEGIN
  BEGIN
    INSERT INTO entry (tracker_id, periodicity, entry_date) VALUES
      ('10000000-0000-4000-8000-000000000001','DAILY','2026-10-05');
    RAISE EXCEPTION 'Дубликат записи принят';
  EXCEPTION WHEN unique_violation THEN RAISE NOTICE 'OK: дубликат даты отклонён (23505)'; END;
  BEGIN
    INSERT INTO entry (tracker_id, periodicity, entry_date) VALUES
      ('10000000-0000-4000-8000-000000000002','WEEKLY','2026-10-06');
    RAISE EXCEPTION 'Недельная запись за вторник принята';
  EXCEPTION WHEN check_violation THEN RAISE NOTICE 'OK: недельная дата отклонена (23514)'; END;
  BEGIN
    INSERT INTO field_value(entry_id, field_id, tracker_id, kind, text_value) VALUES
      ('30000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000007',
       '10000000-0000-4000-8000-000000000001','TEXT','чужое поле');
    RAISE EXCEPTION 'Чужое поле принято';
  EXCEPTION WHEN foreign_key_violation THEN RAISE NOTICE 'OK: поле другого трекера отклонено (23503)'; END;
  BEGIN
    UPDATE field_value SET number_value = 11 WHERE kind = 'SCALE';
    RAISE EXCEPTION 'Оценка вне шкалы принята';
  EXCEPTION WHEN check_violation THEN RAISE NOTICE 'OK: оценка 11 отклонена (23514)'; END;
  BEGIN
    UPDATE goal SET group_id = '40000000-0000-4000-8000-000000000002';
    RAISE EXCEPTION 'Группа другого пользователя принята';
  EXCEPTION WHEN foreign_key_violation THEN RAISE NOTICE 'OK: чужая группа целей отклонена (23503)'; END;
  BEGIN
    INSERT INTO ai_summary(user_id,starts_on,ends_before,summary_text)
      SELECT user_id,starts_on,ends_before,'Дубликат' FROM ai_summary;
    RAISE EXCEPTION 'Дубликат сводки принят';
  EXCEPTION WHEN unique_violation THEN RAISE NOTICE 'OK: дубликат сводки отклонён (23505)'; END;
END $$;

\ir 04_save_entry.sql
\ir 04_save_entry.sql
\ir 05_confirm_payment.sql
\ir 05_confirm_payment.sql
SELECT :ROW_COUNT = 0 AS replay_ignored \gset
\if :replay_ignored
  \echo 'OK: повторный callback не обновил ни одной строки'
\else
  DO $$ BEGIN RAISE EXCEPTION 'Повторный callback обновил подписку'; END $$;
\endif

DO $$
BEGIN
  IF (SELECT status FROM entry_status WHERE entry_date = DATE '2026-10-07')
       IS DISTINCT FROM 'COMPLETE'
     OR (SELECT count(*) FROM entry WHERE entry_date = DATE '2026-10-07') <> 1
     OR (SELECT number_value FROM field_value
         WHERE entry_id = '30000000-0000-4000-8000-000000000003' AND kind = 'SCALE')
        IS DISTINCT FROM 9 THEN
    RAISE EXCEPTION 'UC-01: повторное сохранение не дало ожидаемого результата';
  END IF;
  IF (SELECT p.status || '/' || s.tariff FROM payment p JOIN subscription s ON s.id=p.subscription_id
      WHERE p.provider_payment_id='demo-created-002') IS DISTINCT FROM 'PAID/PRO'
     OR (SELECT ends_before FROM subscription WHERE user_id='00000000-0000-4000-8000-000000000002')
          IS DISTINCT FROM DATE '2026-11-08' THEN
    RAISE EXCEPTION 'UC-04: неверное состояние после callback';
  END IF;
  RAISE NOTICE 'OK: повторное сохранение оставило 1 запись, callback активировал PRO';
END $$;
ROLLBACK;
