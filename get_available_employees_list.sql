-- Get available employee from spa center by services list and date & time.
-- Service Ids will passed as comma separated
DROP FUNCTION get_available_employees_list;
CREATE OR REPLACE FUNCTION get_available_employees_list(
	service_ids text,
	center_id bigint,
	checking_date date,
	checking_time time
)
RETURNS json
LANGUAGE 'plpgsql'

COST 100
VOLATILE 
    
AS $BODY$

declare
	service_id_list bigint [];
	end_time time;
	day_of_week int;
	is_open boolean;
	services_duration int;
	found_employees json;
BEGIN
	
	service_id_list := string_to_array(service_ids, ',');

	day_of_week := (SELECT (EXTRACT(DOW FROM checking_date) + 1));
		
	-- Check business orpen or not
	is_open := (SELECT true FROM business_hour where day_number = day_of_week and business_hour.center_id = get_available_employees_list.center_id);
	if is_open is null then
		RAISE WARNING 'Businness is not open';
		return null;
	end if;
	
	-- Get Sum of the services duration in minute
	SELECT INTO services_duration sum(duration) FROM service where id = ANY(service_id_list);
	if services_duration is null then
		RAISE WARNING 'Services id % is not found', service_ids;
		return null;
	end if;

	end_time := checking_time + (services_duration * (interval '1 minute'));
	select into found_employees json_agg(row_to_json(row))
		from (
			SELECT employee.*,
				(
					SELECT  
						avg(review.stars)::NUMERIC(2,1)
					FROM 
						review
						LEFT JOIN invoice ON invoice.id = review.invoice_id 
					WHERE 
						exists (select id from invoice_detail where employee_id = 1 and invoice_id = review.invoice_id)
				) as average_review
			FROM 
				employee
			WHERE
				spa_center_id = get_available_employees_list.center_id AND 
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
			) row;
	
	RETURN found_employees;
end;

$BODY$;

COMMENT ON FUNCTION get_available_employees_list IS 'Get available employee from spa center by services list and date & time. Service Ids will passed as comma separated';