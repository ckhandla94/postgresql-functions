-- Get available employee from spa center by services list and date & time who have least booking on the day.
-- Service Ids will passed as comma separated
CREATE OR REPLACE FUNCTION get_least_bookings_employee(
	service_ids text,
	staff_ids text,
	checking_date date,
	checking_time time
)
RETURNS bigint
LANGUAGE 'plpgsql'

COST 100
VOLATILE 
    
AS $BODY$

declare
	available_employee_list bigint[];
	service_id_list bigint[];
	staff_id_list bigint[];
	found_employee_id bigint;
	end_time time;
	services_duration bigint;
	employees json;
BEGIN

	service_id_list := string_to_array(service_ids, ',');
	staff_id_list := string_to_array(staff_ids, ',');

	SELECT INTO services_duration sum(duration) FROM service where id = ANY(service_id_list);

	if services_duration is null then
		RAISE WARNING 'Services id % is not found', service_ids;
		return null;
	end if;

	end_time := checking_time + (services_duration * (interval '1 minute'));
	SELECT into staff_id_list array_agg(id) FROM employee 
		WHERE
			id = ANY(staff_id_list) AND 
			EXISTS (
				SELECT employee_id FROM employee_service WHERE employee_id = employee.id GROUP BY employee_id HAVING array_agg(service_id) @> service_id_list 
			) AND
			EXISTS (
				SELECT employee_id FROM office_hour 
				WHERE 
					employee_id = employee.id AND 
					TO_TIMESTAMP(concat(start_hour, ':', start_minute), 'HH24:MI')::time <= checking_time AND 
					TO_TIMESTAMP(concat(end_hour, ':', end_minute), 'HH24:MI')::time >= checking_time AND 
					day_number = day_of_week 
			) AND
			NOT EXISTS (
				SELECT booking_detail.id FROM booking_detail LEFT JOIN booking ON booking.id = booking_detail.booking_id WHERE ( TO_TIMESTAMP(concat(booking_detail.start_hour, ':' ,booking_detail.start_minute), 'HH24:MI')::time, TO_TIMESTAMP(concat(booking_detail.end_hour, ':' ,booking_detail.end_minute), 'HH24:MI')::time ) OVERLAPS ( checking_time, end_time ) AND booking_detail.employee_id = employee.id AND booking_detail.selected_date::date = checking_date::date AND booking.status != 'Canceled'
			)
		GROUP BY 1;
	

	IF staff_id_list IS NOT NULL THEN 
		-- Check employee has booking and get employee who has no booking or who was finished booking early.
		SELECT 
			INTO found_employee_id
			employee.id,
			( SELECT count(booking_detail.id) FROM booking_detail LEFT JOIN booking ON booking_detail.booking_id = booking.id WHERE booking_detail.employee_id = employee.id AND booking_detail.selected_date::date = checking_date::date  AND bookings.status != 'Canceled' ) as bookings_count
		FROM 
			employee
			LEFT JOIN booking_detail ON employee.id = booking_detail.employee_id
		WHERE
			employee.id = ANY(staff_id_list)
		GROUP BY 
			employee.id
		ORDER BY
			bookings_count ASC;
	END IF;

	RETURN found_employee_id;

end;

$BODY$;

COMMENT ON FUNCTION get_least_bookings_employee IS 'Get available employee from spa center by services list and date & time who have least booking on the day. Service Ids will passed as comma separated';