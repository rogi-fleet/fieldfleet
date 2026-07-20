
  -- Status-transition enforcement triggers for work_orders and subcontracts.
  -- Rejects any UPDATE that moves status to an edge not in the allowed set.

  CREATE OR REPLACE FUNCTION enforce_work_order_status_transition()
  RETURNS TRIGGER LANGUAGE plpgsql AS $$
  DECLARE
    allowed boolean := false;
  BEGIN
    IF NEW.status = OLD.status THEN
      RETURN NEW;
    END IF;
    allowed := CASE OLD.status
      WHEN 'draft'       THEN NEW.status IN ('issued', 'cancelled')
      WHEN 'issued'      THEN NEW.status IN ('in_progress', 'on_hold', 'cancelled')
      WHEN 'in_progress' THEN NEW.status IN ('on_hold', 'completed', 'cancelled')
      WHEN 'on_hold'     THEN NEW.status IN ('in_progress', 'cancelled')
      WHEN 'completed'   THEN false
      WHEN 'cancelled'   THEN false
      ELSE false
    END;
    IF NOT allowed THEN
      RAISE EXCEPTION 'Invalid work order status transition: % -> %', OLD.status, NEW.status
        USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
  END;
  $$;

  DROP TRIGGER IF EXISTS work_orders_status_transition ON work_orders;
  CREATE TRIGGER work_orders_status_transition
    BEFORE UPDATE OF status ON work_orders
    FOR EACH ROW EXECUTE FUNCTION enforce_work_order_status_transition();

  CREATE OR REPLACE FUNCTION enforce_subcontract_status_transition()
  RETURNS TRIGGER LANGUAGE plpgsql AS $$
  DECLARE
    allowed boolean := false;
  BEGIN
    IF NEW.status = OLD.status THEN
      RETURN NEW;
    END IF;
    allowed := CASE OLD.status
      WHEN 'draft'      THEN NEW.status IN ('sent', 'cancelled')
      WHEN 'sent'       THEN NEW.status IN ('signed', 'cancelled')
      WHEN 'signed'     THEN NEW.status IN ('active', 'terminated')
      WHEN 'active'     THEN NEW.status IN ('completed', 'terminated')
      WHEN 'completed'  THEN false
      WHEN 'terminated' THEN false
      WHEN 'cancelled'  THEN false
      ELSE false
    END;
    IF NOT allowed THEN
      RAISE EXCEPTION 'Invalid subcontract status transition: % -> %', OLD.status, NEW.status
        USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
  END;
  $$;

  DROP TRIGGER IF EXISTS subcontracts_status_transition ON subcontracts;
  CREATE TRIGGER subcontracts_status_transition
    BEFORE UPDATE OF status ON subcontracts
    FOR EACH ROW EXECUTE FUNCTION enforce_subcontract_status_transition();
  