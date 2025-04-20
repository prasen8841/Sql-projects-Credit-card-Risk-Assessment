create database credit_card_approval;

use credit_card_approval;

create table cards_data(
id int,
client_id int,
card_brand text,
card_type text,
card_number	bigint,
expires	text,
cvv	int,
has_chip text,
num_cards_issued int,
credit_limit text,
acct_open_date text,
year_pin_last_changed int,
card_on_dark_web text
);

select * from cards_data;

create table users_data(
id int,
current_age	int,
retirement_age int,
birth_year	int,
birth_month	int,
gender text,
address	text,
latitude text,
longitude text,
per_capita_income int,	
yearly_income int,
total_debt int,
credit_score int,	
num_credit_cards int
);


create table transactions_data(
id int,
`date` text,
client_id int,
card_id int,
amount text,
use_chip text,
merchant_id	int,
merchant_city text,
merchant_state text,
zip	int,
mcc int,
`errors` text
);

select * from transactions_data;

set sql_safe_updates = 0;
update transactions_data
set amount = replace(amount,"$","");

alter table transactions_data
modify column amount decimal(10,2);

update cards_data
set credit_limit = replace(credit_limit,"$","");

alter table cards_data
modify column credit_limit decimal(10,2);

alter table cards_data 
add column expiration_date date;

update cards_data
set expires = str_to_date(expires, "%m %Y");

alter table users_data
rename column id to client_id;

alter table cards_data
rename column id to card_id;

alter table transactions_data
rename column id to transaction_id;

/*Customer Spending Behavior & Segmentation
1.Which customers have spent the most money using their credit cards?
→ Helps identify premium or high-value customers fro exclusive offers.*/
select td.client_id, round(sum(td.amount),2) as Total_spending
from transactions_data td inner join users_data ud using(client_id)
group by td.client_id
order by Total_spending desc
limit 10;

/*2.What is the average credit limit per income bracket?
This helps assess if credit allocation aligns with income levels.*/
select 
	case
		when yearly_income < 40000 Then "Low Income(<$40,000)"
		when yearly_income between  40000 and 80000 
        Then "Mid Income ($40,000-$80,000)"
        when yearly_income > 80000 Then "High Income (>80,000)"
        end AS Income_Bracket,     
		round(avg(c.credit_limit),2) as Avg_Credit_Limit
from users_data u join cards_data c using(client_id)
group by Income_Bracket;

/*3.Which age group spends the most on credit cards?
This insight is useful for targeted promotions*/
select 
	  case
		  when current_age between 18 and 25 then "18-25"
          when current_age between 26 and 35 then "26-35"
          when current_age between 36 and 50 then "36-50"
		  when current_age between 51 and 60 then "51-60"
		  else "60+"
          end as Age_Group,
          round(sum(t.amount),2) as Total_Spent
from users_data u join transactions_data t using(client_id)
group by Age_Group
order by Total_Spent desc; 

/*4.Do users with more credit cards spend more?
This checks if card ownership influences spending behavior.*/
select u.num_credit_cards, round(avg(t.amount),2) as Average_Transaction
from users_data u left join transactions_data t using(client_id)
group by u.num_credit_cards
order by Average_Transaction desc; 

/*5.Which customers have high debt but low yearly income?
These customers may be at risk of financial distress.*/
with Risk_Analysis as(
select client_id,yearly_income,total_debt,
case
	when total_debt > yearly_income * 1.5 Then "High Risk"
	else "Low Risk"
end as Risk_level-- debt is 150% or more of income
from users_data)

select Risk_level,count(*) as Risk_Count
from Risk_Analysis
Group by Risk_Level;

/*6.How many users are inactive (haven't made transactions in the last 6 months)?
→ Helps with customer retention strategies.*/
with Inactive_state as(select distinct client_id,
	case 	
		when str_to_date(`date`,"%d-%m-%Y %H:%i") < 
		(SELECT DATE_SUB(MAX(STR_TO_DATE(date, '%d-%m-%Y %H:%i')), INTERVAL 6 MONTH) 
		FROM transactions_data)
		then "Inactive" else "Active" end as Status
from transactions_data)

select status,count(*) as Number_Of_Customers
from Inactive_state   
group by Status;

/*7.Which customers are approaching their credit limit?
Identifying these customers can help offer credit limit increases or 
financial advice.*/
select c.client_id,c.card_id,credit_limit,round(sum(t.amount),2) as Total_Spent,
	   round(credit_limit - sum(t.amount),2) as Remaining_limit
from cards_data c join transactions_data t using(client_id)
group by c.client_id,c.card_id,credit_limit
having Remaining_limit < (credit_limit * 0.1) and Remaining_limit > 0 
-- less than 10% limit left
order by Remaining_limit;

/*8.How does transaction frequency change over time (seasonality)?
Understanding seasonal spending can improve marketing campaigns*/
select monthname(str_to_date(date,"%m-%d-%Y %H:%i")) as Month,
	count(*) as Transaction_Count,
	round(sum(amount),2) as Total_Spent
    FROM transactions_data
where monthname(str_to_date(date,"%m-%d-%Y %H:%i")) <> ""
group by Month
order by Month;

/*Merchant & Transaction Analytics
9.Which merchants have the highest transaction volumes?
- Helps in targeted marketing campaigns.*/
select merchant_id,round(sum(amount),2) as Transaction_Volume
from transactions_data
group by merchant_id
order by Transaction_Volume desc
limit 10;

/*10.What percent of total transaction were offline and online?
→ Analyzing the number of online vs. offline transactions for a credit card can 
provide valuable insights into customer behavior and business strategy..*/
select 
	count(transaction_id) as Total_transaction,
	sum(case when use_chip = "Online Transaction" then 1 else 0 end)
    /count(transaction_id)  as Percent_Online_Transactions,
    sum(case when use_chip = "Swipe Transaction" then 1 else 0 end)
    /count(transaction_id)  as Percent_Offline_Transactions
from transactions_data;

/*11.Which card brand is preferred more by the customers?
Understanding which card brands drive higher spending can help in
targeted marketing.*/
select c.card_brand,count(t.transaction_id) as Total_Transaction
from cards_data c join transactions_data t using(client_id)
group by c.card_brand
order by Total_Transaction desc; 

/*12.Which merchants frequently have transactions with errors?
Frequent transaction failures may indicate issues with payment processing.*/
select merchant_id,count(*) as Total_Transactions,
	   sum(case when `errors` <> "" then 1 else 0 end) as Failed_Transactions,
       (sum(case when `errors` <> "" then 1 else 0 end)/count(*)) * 100 as Failure_rate
       from transactions_data
group by merchant_id
having Failure_rate > 60 -- filtering merchants with more than 5% failure rate
order by Failed_Transactions desc; 

/*Fraud Detection & Risk Assessment
/*13.What are the top error types in transactions?
Understanding errors can help optimize the transaction process*/
select `errors`,count(*) as Error_count
from transactions_data
where `errors` not like ""
group by `errors`
order by Error_Count desc; 

/*14.Are there users making transactions in multiple cities within the same day?
-Could indicate potential fraud.*/
select client_id,date,count(distinct(merchant_city)) as Unique_Cities
from transactions_data
group by client_id,date
having Unique_Cities > 1;

/*15.Are there users making unusually high transactions in a short time span?
→ Helps detect potential fraud cases.*/
WITH transactions_time AS (
    SELECT card_id ,
        STR_TO_DATE(date, '%d-%m-%Y %H:%i') AS transaction_time 
    FROM transactions_data
),
transaction_counts AS (
    SELECT t1.card_id, t1.transaction_time, 
        COUNT(*) OVER (PARTITION BY t1.card_id
        ORDER BY t1.transaction_time RANGE INTERVAL 20 MINUTE PRECEDING) AS transaction_count
    FROM transactions_time t1
)
SELECT DISTINCT card_id, COUNT(*) as total_transactions
FROM transaction_counts
WHERE transaction_count > 5  -- Threshold for 'numerous transactions'
GROUP BY card_id
having total_transactions > 5
ORDER BY total_transactions DESC;

/*16.Which users have multiple declined transactions?
→ Helps flag potential fraudulent or blocked accounts.*/
select client_id,count(`errors`) as Declined_Transactions
from transactions_data
where `errors` is not null
group by client_id
having Declined_transactions > 5;  

/*17.Finds users making multiple transactions at risky MCCs (e.g., gambling, cryptocurrency, gift cards).
High-Risk MCCs Attract Fraudsters – Fraudsters often use gambling sites, cryptocurrency platforms, or 
prepaid gift cards to launder money or test stolen cards.*/
SELECT client_id, COUNT(*) AS risky_txns, round(SUM(amount),2) AS total_spent
FROM transactions_data
WHERE mcc IN ('7995', '6012', '4829')  -- MCC for gambling, crypto, money transfer
GROUP BY client_id
HAVING risky_txns > 10 and total_spent > 20000;

/*18.Multiple Cards Used on Same Merchant/Device/IP
Fraudsters test stolen credit card numbers by making small transactions at a single merchant (e.g., $1 transactions).*/
SELECT merchant_id, COUNT(DISTINCT card_id) AS unique_cards, COUNT(*) AS txn_count,sum(amount) as Total_Spent
FROM transactions_data
GROUP BY merchant_id
HAVING unique_cards =1 and txn_count >3 ;


    




















