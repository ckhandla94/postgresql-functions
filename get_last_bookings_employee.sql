-- Get available employee from spa center by services list and date & time.
-- Service Ids will passed as comma separated

CREATE OR REPLACE FUNCTION get_last_bookings_employee(
	service_ids text,
	center_id bigint,
	checking_date date,
	checking_time time
)
RETURNS bigint
LANGUAGE 'plpgsql'

COST 100
VOLATILE 
    
AS $BODY$

declare
	service_id_list bigint [];
	staff_ids text;
	employees json;
	end_time time;
	day_of_week int;
	is_open boolean;
	available_employee_list bigint[];
	services_duration int;
	found_employee_id bigint;
	i json;
BEGIN

	--SELECT INTO staff_ids array_to_string(array_agg(id), ',') FROM employee WHERE spa_center_id = get_last_bookings_employee.center_id GROUP BY spa_center_id;
	
	employees = get_available_employees_list(service_ids, center_id, checking_date, checking_time);

	if employees is null then
		return null;
	end if;
	
	RAISE WARNING 'employees = %', employees; 
	
	FOR i IN SELECT * FROM json_array_elements(employees) LOOP
		 RAISE NOTICE 'output from space %', i->>'id';
		 available_employee_list := array_append(available_employee_list, (i->>'id')::bigint);
		
	END LOOP;


	RAISE WARNING 'available_employee_list = %', available_employee_list; 

			
	IF available_employee_list IS NOT NULL THEN 
		end_time := checking_time + (services_duration * (interval '1 minute'));

		-- Check employee has booking and get employee who has no booking or who was finished booking early.
		SELECT 
			INTO found_employee_id
			employee.id,
			( SELECT MAX(TO_TIMESTAMP(concat(booking_detail.end_hour, ':', booking_detail.end_minute), 'HH24:MI')::time) as time FROM booking_detail  LEFT JOIN booking ON booking_detail.booking_id = booking.id WHERE booking_detail.employee_id = employee.id AND booking_detail.selected_date::date = checking_date::date  AND booking.status != 'Canceled'  ) as bookings_time
		FROM 
			employee
			LEFT JOIN booking_detail ON employee.id = booking_detail.employee_id
		WHERE
			employee.id = ANY(available_employee_list) AND 
			NOT EXISTS (
				SELECT id FROM booking_detail WHERE ( TO_TIMESTAMP(concat(start_hour, ':' ,start_minute), 'HH24:MI')::time, TO_TIMESTAMP(concat(end_hour, ':' ,end_minute), 'HH24:MI')::time ) OVERLAPS ( checking_time, end_time ) AND employee_id = employee.id AND selected_date::date = checking_date::date
			)
		GROUP BY 
			employee.id
		ORDER BY
			bookings_time ASC NULLS FIRST;
	END IF;

	RETURN found_employee_id;

end;

$BODY$;

COMMENT ON FUNCTION get_last_bookings_employee IS 'Get available employee from spa center by services list and date & time. Service Ids will passed as comma separated';