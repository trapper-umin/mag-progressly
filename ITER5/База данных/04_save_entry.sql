-- Демонстрация UC-01: сохранить/обновить одно значение под существующим владельцем.
-- Запускать внутри транзакции. Правила config и пересчёт стрика — в сервисе.
SET search_path TO progressly, public;
WITH saved AS (
  INSERT INTO entry (tracker_id, periodicity, entry_date, updated_at)
  SELECT id, periodicity, DATE '2026-10-07', TIMESTAMPTZ '2026-10-08 10:00+00'
  FROM tracker WHERE id = '10000000-0000-4000-8000-000000000001'
    AND user_id = '00000000-0000-4000-8000-000000000001' AND active
  ON CONFLICT (tracker_id, entry_date) DO UPDATE SET updated_at = excluded.updated_at
  RETURNING id, tracker_id
)
INSERT INTO field_value (entry_id, field_id, tracker_id, kind, number_value)
SELECT id, '20000000-0000-4000-8000-000000000002', tracker_id, 'SCALE', 9
FROM saved
ON CONFLICT (entry_id, field_id) DO UPDATE SET number_value = excluded.number_value
RETURNING entry_id, kind, number_value;
