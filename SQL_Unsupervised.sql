-- Sessions aggregieren: Nutzerverhalten

WITH session_agg AS (
    SELECT
        user_id,
        COUNT(*) AS session_count,
        AVG(page_clicks) AS avg_page_clicks,
        AVG(EXTRACT(EPOCH FROM (session_end - session_start)) / 60) AS avg_session_duration_min,
        AVG(CASE WHEN flight_booked THEN 1 ELSE 0 END) AS flight_booking_rate,
        AVG(CASE WHEN hotel_booked THEN 1 ELSE 0 END) AS hotel_booking_rate,
        AVG(CASE WHEN cancellation THEN 1 ELSE 0 END) AS cancellation_rate,
        AVG(CASE WHEN flight_discount THEN flight_discount_amount ELSE NULL END) AS avg_flight_discount,
        AVG(CASE WHEN hotel_discount THEN hotel_discount_amount ELSE NULL END) AS avg_hotel_discount
    FROM sessions
    WHERE session_start >= '2023-01-04'
      AND session_start <= CURRENT_DATE
    GROUP BY user_id
),

-- Flüge aggregieren: Reiseverhalten
flight_agg AS (
    SELECT
        u.user_id,
        COUNT(*) AS num_flights,
        AVG(seats) AS avg_seats_per_trip,
        AVG(base_fare_usd) AS avg_base_fare,
        AVG(checked_bags) AS avg_checked_bags,
        AVG(CASE WHEN return_flight_booked THEN 1 ELSE 0 END) AS return_flight_ratio,
        AVG(
            sqrt(
                POWER(destination_airport_lat - u.home_airport_lat, 2) +
                POWER(destination_airport_lon - u.home_airport_lon, 2)
            )
        ) AS avg_trip_distance
    FROM flights f
    JOIN sessions s ON f.trip_id = s.trip_id
    JOIN users u ON s.user_id = u.user_id
    WHERE s.session_start >= '2023-01-04'
      AND s.session_start <= CURRENT_DATE
    GROUP BY u.user_id
),

-- Hotels aggregieren: Unterkunftsverhalten

hotel_agg AS (
    SELECT
        u.user_id,
        COUNT(*) AS num_hotel_stays,
        AVG(nights) AS avg_nights,
        AVG(rooms) AS avg_rooms,
        AVG(hotel_per_room_usd) AS avg_price_per_room
    FROM hotels h
    JOIN sessions s ON h.trip_id = s.trip_id
    JOIN users u ON s.user_id = u.user_id
    WHERE s.session_start >= '2023-01-04'
      AND s.session_start <= CURRENT_DATE
    GROUP BY u.user_id
),

-- Alles kombinieren: Nutzerprofil mit Verhalten

final AS (
    SELECT
        u.user_id,
        -- Demographics
        DATE_PART('year', AGE(u.birthdate)) AS age,
        u.gender,
        u.married::int AS is_married,
        u.has_children::int AS has_children,
        u.home_country,
        u.home_city,
        u.home_airport_lat,
        u.home_airport_lon,
        (CURRENT_DATE - u.sign_up_date)::int AS account_age_days,

        -- Sessions
        sa.session_count,
        sa.avg_page_clicks,
        sa.avg_session_duration_min,
        sa.flight_booking_rate,
        sa.hotel_booking_rate,
        sa.cancellation_rate,
        sa.avg_flight_discount,
        sa.avg_hotel_discount,

        -- Flights
        fa.num_flights,
        fa.avg_seats_per_trip,
        fa.avg_base_fare,
        fa.avg_checked_bags,
        fa.return_flight_ratio,
        fa.avg_trip_distance,

        -- Hotels
        ha.num_hotel_stays,
        ha.avg_nights,
        ha.avg_rooms,
        ha.avg_price_per_room

    FROM users u
    LEFT JOIN session_agg sa ON u.user_id = sa.user_id
    LEFT JOIN flight_agg fa ON u.user_id = fa.user_id
    LEFT JOIN hotel_agg ha ON u.user_id = ha.user_id
)

-- Finale Tabelle für ML-Input

SELECT *
FROM final;