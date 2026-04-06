-- ============================================================
-- LogBook ATPL – Schema Supabase
-- Esegui questo script in: Supabase Dashboard → SQL Editor
-- ============================================================

CREATE TABLE IF NOT EXISTS public.flights (
    id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Date & Route
    date                  DATE            NOT NULL,
    departure_place       TEXT            NOT NULL DEFAULT '',
    departure_time        TIMESTAMPTZ,
    arrival_place         TEXT            NOT NULL DEFAULT '',
    arrival_time          TIMESTAMPTZ,

    -- Aircraft
    aircraft_type         TEXT            NOT NULL DEFAULT '',
    aircraft_registration TEXT            NOT NULL DEFAULT '',

    -- Single Pilot Time (ore)
    se_single_pilot_time  DOUBLE PRECISION NOT NULL DEFAULT 0,
    me_single_pilot_time  DOUBLE PRECISION NOT NULL DEFAULT 0,

    -- Multi Pilot Time (ore)
    multi_pilot_time      DOUBLE PRECISION NOT NULL DEFAULT 0,

    -- Total Flight Time (ore)
    total_flight_time     DOUBLE PRECISION NOT NULL DEFAULT 0,

    -- PIC Name
    pic_name              TEXT            NOT NULL DEFAULT '',

    -- Landings
    day_landings          INTEGER         NOT NULL DEFAULT 0,
    night_landings        INTEGER         NOT NULL DEFAULT 0,

    -- Operational Condition Time (ore)
    night_time            DOUBLE PRECISION NOT NULL DEFAULT 0,
    ifr_time              DOUBLE PRECISION NOT NULL DEFAULT 0,

    -- Pilot Function Time (ore)
    pic_time              DOUBLE PRECISION NOT NULL DEFAULT 0,
    co_pilot_time         DOUBLE PRECISION NOT NULL DEFAULT 0,
    dual_time             DOUBLE PRECISION NOT NULL DEFAULT 0,
    instructor_time       DOUBLE PRECISION NOT NULL DEFAULT 0,

    -- FSTD / Simulator
    fstd_type             TEXT            NOT NULL DEFAULT '',
    fstd_time             DOUBLE PRECISION NOT NULL DEFAULT 0,

    -- Remarks
    remarks               TEXT            NOT NULL DEFAULT '',

    -- Metadata
    created_at            TIMESTAMPTZ     NOT NULL DEFAULT now(),
    updated_at            TIMESTAMPTZ     NOT NULL DEFAULT now()
);

-- Indice per query per data
CREATE INDEX IF NOT EXISTS idx_flights_date ON public.flights (date DESC);

-- Trigger: aggiorna updated_at automaticamente
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS flights_set_updated_at ON public.flights;
CREATE TRIGGER flights_set_updated_at
    BEFORE UPDATE ON public.flights
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ============================================================
-- Row Level Security (opzionale per uso personale)
-- Abilita se vuoi proteggere i dati con autenticazione Supabase.
-- Per uso personale senza auth puoi lasciare RLS disabilitata.
-- ============================================================

-- ALTER TABLE public.flights ENABLE ROW LEVEL SECURITY;
-- CREATE POLICY "Solo utente autenticato" ON public.flights
--     USING (auth.role() = 'authenticated');

-- ============================================================
-- Strategia di merge offline-first (upsert con updated_at)
-- Il client invia: Prefer: resolution=merge-duplicates
-- Vince il record con updated_at più recente.
-- ============================================================

-- Permette upsert solo se il record in arrivo è più recente
CREATE OR REPLACE FUNCTION public.upsert_flight_if_newer()
RETURNS TRIGGER AS $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM public.flights
        WHERE id = NEW.id AND updated_at >= NEW.updated_at
    ) THEN
        RETURN NULL;  -- ignora: il server ha una versione più recente
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS flights_upsert_newer ON public.flights;
CREATE TRIGGER flights_upsert_newer
    BEFORE INSERT OR UPDATE ON public.flights
    FOR EACH ROW EXECUTE FUNCTION public.upsert_flight_if_newer();

-- ============================================================
-- Tabella Aircraft (flotta)
-- ============================================================

CREATE TABLE IF NOT EXISTS public.aircraft (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    registration      TEXT            NOT NULL DEFAULT '',
    icao_code         TEXT            NOT NULL DEFAULT '',
    manufacturer      TEXT            NOT NULL DEFAULT '',
    model             TEXT            NOT NULL DEFAULT '',
    variant           TEXT            NOT NULL DEFAULT '',
    serial_number     TEXT            NOT NULL DEFAULT '',
    engine_type       TEXT            NOT NULL DEFAULT '',
    engine_count      INTEGER         NOT NULL DEFAULT 0,
    mtow              TEXT            NOT NULL DEFAULT '',
    first_flight      TEXT            NOT NULL DEFAULT '',
    is_single_engine  BOOLEAN         NOT NULL DEFAULT false,
    is_multi_engine   BOOLEAN         NOT NULL DEFAULT false,
    is_multi_pilot    BOOLEAN         NOT NULL DEFAULT false,
    company           TEXT            NOT NULL DEFAULT '',
    notes             TEXT            NOT NULL DEFAULT '',
    created_at        TIMESTAMPTZ     NOT NULL DEFAULT now(),
    updated_at        TIMESTAMPTZ     NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_aircraft_registration ON public.aircraft (registration);

DROP TRIGGER IF EXISTS aircraft_set_updated_at ON public.aircraft;
CREATE TRIGGER aircraft_set_updated_at
    BEFORE UPDATE ON public.aircraft
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ============================================================
-- Verifica schema
-- ============================================================
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name = 'flights'
ORDER BY ordinal_position;

SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name = 'aircraft'
ORDER BY ordinal_position;
