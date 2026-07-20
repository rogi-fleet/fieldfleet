-- Keep task status/progress/is_complete consistent across all write paths.
CREATE OR REPLACE FUNCTION normalize_task_status_progress()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  -- Normalize common aliases from legacy callers.
  IF NEW.status::text = 'complete' THEN
    NEW.status := 'done'::task_status;
  ELSIF NEW.status::text = 'in_progress' THEN
    NEW.status := 'working_on_it'::task_status;
  ELSIF NEW.status::text = 'blocked' THEN
    NEW.status := 'stuck'::task_status;
  END IF;

  -- Guardrail: status done always means 100%.
  IF NEW.status = 'done'::task_status THEN
    NEW.progress := 100;
  END IF;

  -- Guardrail: 100% progress always means done.
  IF NEW.progress >= 100 THEN
    NEW.progress := 100;
    NEW.status := 'done'::task_status;
  END IF;

  -- Status-based defaults when only status changes.
  IF TG_OP = 'UPDATE'
     AND NEW.status IS DISTINCT FROM OLD.status
     AND NEW.progress IS NOT DISTINCT FROM OLD.progress THEN
    IF NEW.status = 'not_started'::task_status THEN
      NEW.progress := 0;
    ELSIF NEW.status = 'working_on_it'::task_status AND NEW.progress = 0 THEN
      NEW.progress := 10;
    ELSIF NEW.status <> 'done'::task_status AND NEW.progress >= 100 THEN
      NEW.progress := 99;
    END IF;
  END IF;

  -- Unlock from done if user lowers progress without changing status.
  IF TG_OP = 'UPDATE'
     AND NEW.progress IS DISTINCT FROM OLD.progress
     AND NEW.status IS NOT DISTINCT FROM OLD.status
     AND OLD.status = 'done'::task_status
     AND NEW.progress < 100 THEN
    IF NEW.progress = 0 THEN
      NEW.status := 'not_started'::task_status;
    ELSE
      NEW.status := 'working_on_it'::task_status;
    END IF;
  END IF;

  -- Keep non-done progress below 100.
  IF NEW.status <> 'done'::task_status AND NEW.progress >= 100 THEN
    NEW.progress := 99;
  END IF;

  NEW.is_complete := (NEW.status = 'done'::task_status);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_normalize_task_status_progress ON tasks;
CREATE TRIGGER trg_normalize_task_status_progress
BEFORE INSERT OR UPDATE OF status, progress ON tasks
FOR EACH ROW
EXECUTE FUNCTION normalize_task_status_progress();

-- Backfill existing rows to the normalized rules.
UPDATE tasks
SET status = status,
    progress = progress;
