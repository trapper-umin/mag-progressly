-- UC-04: после проверки callback адаптером YooKassa.
-- Один оператор: обновление платежа и прав доступа атомарны.
SET search_path TO progressly, public;
WITH confirmed AS (
  UPDATE payment SET status = 'PAID'
  WHERE provider_payment_id = 'demo-created-002' AND status = 'CREATED'
  RETURNING subscription_id, requested_tariff
)
UPDATE subscription s
SET tariff = c.requested_tariff, starts_on = DATE '2026-10-08',
    ends_before = DATE '2026-11-08', auto_renew = false
FROM confirmed c
WHERE s.id = c.subscription_id
RETURNING s.user_id, s.tariff, s.starts_on, s.ends_before;
