-- Zeitraum definieren

WITH time_bounds AS (
  SELECT
    TIMESTAMP '2021-04-01 00:42:00' AS start_time,
    TIMESTAMP '2023-07-29 01:57:55' AS end_time
),

-- Gesamtzeitraum in 4 gleich große Kohorten teilen

cohort_bounds AS (
  SELECT
    start_time,
    end_time,
    (end_time - start_time) / 4 AS cohort_interval
  FROM time_bounds
),

-- Nutzer-Sessions einer Kohorte zuweisen

user_sessions AS (
  SELECT
    s.user_id,
    s.session_start,
    CASE
      WHEN s.session_start < tb.start_time + cb.cohort_interval THEN 'Cohort 1'
      WHEN s.session_start < tb.start_time + cb.cohort_interval * 2 THEN 'Cohort 2'
      WHEN s.session_start < tb.start_time + cb.cohort_interval * 3 THEN 'Cohort 3'
      ELSE 'Cohort 4'
    END AS cohort
  FROM sessions s
  CROSS JOIN time_bounds tb
  CROSS JOIN cohort_bounds cb
  WHERE s.session_start BETWEEN tb.start_time AND tb.end_time
),

-- Session-Zusammenfassung je Nutzer

user_session_summary AS (
  SELECT
    user_id,
    COUNT(*) AS total_sessions,
    MAX(session_start) AS last_session,
    MIN(cohort) AS start_cohort,
    MAX(cohort) AS end_cohort
  FROM user_sessions
  GROUP BY user_id
),

-- Nutzer in Aktivitätsklassen einteilen

user_classification AS (
  SELECT
    uss.user_id,
    uss.total_sessions,
    uss.last_session,
    uss.start_cohort,
    uss.end_cohort,
    CASE
      WHEN uss.total_sessions <= 3 THEN 'Low Activity User'
      WHEN uss.total_sessions > 7 AND uss.last_session < (SELECT end_time FROM time_bounds) - INTERVAL '4 months'
        THEN 'Get Back User'
      WHEN uss.total_sessions >= 7 THEN 'Active User'
      ELSE 'Inactive User'
    END AS activity_status
  FROM user_session_summary uss
),

-- Sessions aggregieren

session_agg AS (
  SELECT
    user_id,
    COUNT(*) AS total_sessions,
    AVG(page_clicks) AS avg_clicks,
    SUM(CASE WHEN flight_discount THEN 1 ELSE 0 END) AS flight_discounts_used,
    SUM(CASE WHEN hotel_discount THEN 1 ELSE 0 END) AS hotel_discounts_used,
    SUM(CASE WHEN flight_booked THEN 1 ELSE 0 END) AS flights_booked_sessions,
    SUM(CASE WHEN hotel_booked THEN 1 ELSE 0 END) AS hotels_booked_sessions,
    SUM(CASE WHEN cancellation THEN 1 ELSE 0 END) AS cancellations
  FROM sessions
  GROUP BY user_id
),

-- Fluginformationen aggregieren

flight_agg AS (
  SELECT
    s.user_id,
    COUNT(DISTINCT f.trip_id) AS flights_booked,
    SUM(f.seats) AS total_seats_booked,
    ROUND(AVG(f.base_fare_usd), 2) AS avg_base_fare,
    AVG(f.checked_bags) AS avg_bags,
    SUM(CASE WHEN f.return_flight_booked THEN 1 ELSE 0 END) AS returns_booked
  FROM sessions s
  JOIN flights f ON s.trip_id = f.trip_id
  GROUP BY s.user_id
),

-- Hoteldaten aggregieren
hotel_agg AS (
  SELECT
    s.user_id,
    COUNT(DISTINCT h.trip_id) AS hotel_bookings,
    SUM(h.nights) AS total_nights,
    SUM(h.rooms) AS total_rooms,
    ROUND(AVG(h.hotel_per_room_usd), 2) AS avg_price_per_night
  FROM sessions s
  JOIN hotels h ON s.trip_id = h.trip_id
  GROUP BY s.user_id
),

-- Gesamtsumme aller Rabatte pro Nutzer

discount_agg AS (
  SELECT
    s.user_id,
    ROUND(SUM(s.flight_discount_amount * f.base_fare_usd / 100), 2) AS total_flight_discount_usd,
    ROUND(SUM(s.hotel_discount_amount * h.hotel_per_room_usd * h.nights * h.rooms / 100), 2) AS total_hotel_discount_usd
  FROM sessions s
  LEFT JOIN flights f ON s.trip_id = f.trip_id
  LEFT JOIN hotels h ON s.trip_id = h.trip_id
  GROUP BY s.user_id
),

-- Urlaubsart bestimmen: Zuhause vs. auswärts

vacation_type AS (
  SELECT
    u.user_id,
    CASE
      WHEN COUNT(f.trip_id) = 0 THEN 'No Flights'
      WHEN COUNT(*) FILTER (WHERE f.destination = u.home_city) >= COUNT(*) / 2.0 THEN 'Home Vacation'
      ELSE 'Away Vacation'
    END AS vacation_type
  FROM users u
  LEFT JOIN sessions s ON u.user_id = s.user_id
  LEFT JOIN flights f ON s.trip_id = f.trip_id
  GROUP BY u.user_id, u.home_city
),

-- Altersgruppen einteilen

age_groups AS (
  SELECT
    user_id,
    CASE
      WHEN DATE_PART('year', AGE(birthdate)) < 25 THEN '<25'
      WHEN DATE_PART('year', AGE(birthdate)) BETWEEN 25 AND 40 THEN '25-40'
      WHEN DATE_PART('year', AGE(birthdate)) BETWEEN 41 AND 60 THEN '41-60'
      ELSE '>60'
    END AS age_group
  FROM users
),

-- Familienstatus klassifizieren

family_status AS (
  SELECT
    user_id,
    CASE
      WHEN married AND has_children THEN 'Family User'
      WHEN married AND NOT has_children THEN 'Married without Children'
      WHEN NOT married AND has_children THEN 'Single Parent'
      ELSE 'Single without Children'
    END AS family_type
  FROM users
),

-- Lieblingsairline je Nutzer bestimmen

user_top_airline AS (
  SELECT
    user_id,
    trip_airline,
    bookings_with_airline
  FROM (
    SELECT
      s.user_id,
      f.trip_airline,
      COUNT(DISTINCT f.trip_id) AS bookings_with_airline,
      ROW_NUMBER() OVER (PARTITION BY s.user_id ORDER BY COUNT(DISTINCT f.trip_id) DESC) AS rn
    FROM sessions s
    JOIN flights f ON s.trip_id = f.trip_id
    GROUP BY s.user_id, f.trip_airline
  ) sub
  WHERE rn = 1
),

-- Gruppenreise-Flag (3+ Flüge oder 2+ Zimmer)

group_travel_flag AS (
  SELECT
    s.user_id,
    AVG(CASE WHEN f.seats >= 3 THEN 1 ELSE 0 END) AS flight_group_ratio,
    AVG(CASE WHEN h.rooms >= 2 THEN 1 ELSE 0 END) AS hotel_group_ratio
  FROM sessions s
  LEFT JOIN flights f ON s.trip_id = f.trip_id
  LEFT JOIN hotels h ON s.trip_id = h.trip_id
  GROUP BY s.user_id
)

-- Endauswahl: Tabelle für Supervised Learning

SELECT
  u.user_id,
  DATE_PART('year', AGE(u.birthdate)) AS age,
  ag.age_group,
  u.gender,
  u.married,
  u.has_children,
  fs.family_type,
  u.home_country,
  u.home_city,
  u.home_airport,
  u.sign_up_date,

-- Aktivitätsverlauf und Status
  uc.start_cohort,
  uc.end_cohort,
  uc.activity_status,

-- Sessionmetriken
  COALESCE(sa.total_sessions, 0) AS total_sessions,
  COALESCE(sa.avg_clicks, 0) AS avg_page_clicks,
  COALESCE(sa.flight_discounts_used, 0) AS flight_discounts_used,
  COALESCE(sa.hotel_discounts_used, 0) AS hotel_discounts_used,
  COALESCE(sa.flights_booked_sessions, 0) AS sessions_with_flight_booking,
  COALESCE(sa.hotels_booked_sessions, 0) AS sessions_with_hotel_booking,
  COALESCE(sa.cancellations, 0) AS cancellations,

-- Flugbuchungsverhalten
  COALESCE(fa.flights_booked, 0) AS total_flights,
  COALESCE(fa.total_seats_booked, 0) AS total_seats,
  COALESCE(fa.avg_base_fare, 0) AS avg_flight_fare_usd,
  ROUND(COALESCE(fa.avg_bags, 0), 2) AS avg_checked_bags,
  COALESCE(fa.returns_booked, 0) AS return_flights,

-- Hotelverhalten
  COALESCE(ha.hotel_bookings, 0) AS total_hotel_bookings,
  COALESCE(ha.total_nights, 0) AS total_nights_booked,
  COALESCE(ha.total_rooms, 0) AS total_rooms_booked,
  COALESCE(ha.avg_price_per_night, 0) AS avg_hotel_price_usd,

-- Gesamtrabatte
  ROUND(COALESCE(da.total_flight_discount_usd, 0), 2) AS total_flight_discount_usd,
  ROUND(COALESCE(da.total_hotel_discount_usd, 0), 2) AS total_hotel_discount_usd,
  ROUND(COALESCE(da.total_flight_discount_usd, 0) + COALESCE(da.total_hotel_discount_usd, 0), 2) AS total_discount_usd,

  -- Urlaubstyp
  COALESCE(vac.vacation_type, 'Unknown') AS vacation_type,

  -- Gruppenreise-Indikator
  CASE
    WHEN COALESCE(gtf.flight_group_ratio, 0) >= 0.3 OR COALESCE(gtf.hotel_group_ratio, 0) >= 0.3
      THEN TRUE
    ELSE FALSE
  END AS is_group_traveler,

  -- Airline-Treue
  COALESCE(uta.trip_airline, 'Unknown') AS top_airline,
  COALESCE(uta.bookings_with_airline, 0) AS bookings_with_top_airline

FROM users u
LEFT JOIN user_classification uc ON u.user_id = uc.user_id
LEFT JOIN session_agg sa ON u.user_id = sa.user_id
LEFT JOIN flight_agg fa ON u.user_id = fa.user_id
LEFT JOIN hotel_agg ha ON u.user_id = ha.user_id
LEFT JOIN discount_agg da ON u.user_id = da.user_id
LEFT JOIN vacation_type vac ON u.user_id = vac.user_id
LEFT JOIN age_groups ag ON u.user_id = ag.user_id
LEFT JOIN family_status fs ON u.user_id = fs.user_id
LEFT JOIN group_travel_flag gtf ON u.user_id = gtf.user_id
LEFT JOIN user_top_airline uta ON u.user_id = uta.user_id

ORDER BY u.user_id;
