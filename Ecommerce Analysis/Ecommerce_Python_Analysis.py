# ============================================================
# E-COMMERCE CUSTOMER ANALYSIS — PYTHON (PANDAS)
# Krish Surana | Data Analysis Project
# ============================================================

import pandas as pd
import numpy as np
from datetime import datetime, timedelta
import random

# ─────────────────────────────────────────────
# STEP 1: GENERATE SYNTHETIC DATASET (1,000+ records)
# ─────────────────────────────────────────────

np.random.seed(42)
random.seed(42)

n = 1200  # 1,200 transactions

regions = ['North', 'South', 'East', 'West', 'Central']
categories = ['Electronics', 'Apparel', 'Home & Kitchen', 'Books', 'Sports', 'Beauty']
base_date = datetime(2023, 1, 1)

data = {
    'order_id': [f'ORD{str(i).zfill(5)}' for i in range(1, n+1)],
    'customer_id': [f'CUST{str(random.randint(1, 250)).zfill(4)}' for _ in range(n)],
    'order_date': [base_date + timedelta(days=random.randint(0, 364)) for _ in range(n)],
    'product_id': [f'PROD{str(random.randint(1, 80)).zfill(3)}' for _ in range(n)],
    'category': [random.choice(categories) for _ in range(n)],
    'region': [random.choice(regions) for _ in range(n)],
    'revenue': np.round(np.random.lognormal(mean=5.5, sigma=0.8, size=n), 2),
    'quantity': np.random.randint(1, 6, size=n),
    'discount_pct': np.round(np.random.uniform(0, 0.30, size=n), 2),
}

df = pd.DataFrame(data)
df['order_date'] = pd.to_datetime(df['order_date'])
df['month'] = df['order_date'].dt.to_period('M')
df['quarter'] = df['order_date'].dt.to_period('Q')

print("=" * 60)
print("E-COMMERCE DATA ANALYSIS — KRISH SURANA")
print("=" * 60)

# ─────────────────────────────────────────────
# STEP 2: DATA CLEANING & QUALITY CHECKS
# ─────────────────────────────────────────────

print("\n[1] DATA QUALITY CHECK")
print(f"Total Records     : {len(df):,}")
print(f"Null Values       : {df.isnull().sum().sum()}")
print(f"Duplicate Orders  : {df['order_id'].duplicated().sum()}")
print(f"Date Range        : {df['order_date'].min().date()} to {df['order_date'].max().date()}")
print(f"Unique Customers  : {df['customer_id'].nunique():,}")
print(f"Unique Products   : {df['product_id'].nunique():,}")

# Remove outliers (revenue > 3 std devs)
mean_rev = df['revenue'].mean()
std_rev = df['revenue'].std()
df['z_score'] = (df['revenue'] - mean_rev) / std_rev
outliers = df[df['z_score'].abs() > 3]
print(f"Outliers Removed  : {len(outliers)} records")
df_clean = df[df['z_score'].abs() <= 3].copy()
print(f"Clean Records     : {len(df_clean):,}")

# ─────────────────────────────────────────────
# STEP 3: REVENUE ANALYSIS
# ─────────────────────────────────────────────

print("\n[2] REVENUE SUMMARY")
print(f"Total Revenue     : ₹{df_clean['revenue'].sum():,.0f}")
print(f"Avg Order Value   : ₹{df_clean['revenue'].mean():,.0f}")
print(f"Median Order Value: ₹{df_clean['revenue'].median():,.0f}")
print(f"Total Orders      : {len(df_clean):,}")

# Monthly revenue
monthly = df_clean.groupby('month').agg(
    orders=('order_id','count'),
    revenue=('revenue','sum'),
    customers=('customer_id','nunique')
).reset_index()
monthly['avg_order_value'] = monthly['revenue'] / monthly['orders']
monthly['mom_growth'] = monthly['revenue'].pct_change() * 100

print("\n[3] MONTHLY REVENUE (Top 6 months)")
print(monthly[['month','orders','revenue','avg_order_value']].tail(6).to_string(index=False))

# Category analysis
print("\n[4] REVENUE BY CATEGORY")
cat_analysis = df_clean.groupby('category').agg(
    orders=('order_id','count'),
    revenue=('revenue','sum'),
    avg_value=('revenue','mean')
).reset_index()
cat_analysis['revenue_share'] = (cat_analysis['revenue'] / cat_analysis['revenue'].sum() * 100).round(1)
cat_analysis = cat_analysis.sort_values('revenue', ascending=False)
print(cat_analysis.to_string(index=False))

# Region analysis
print("\n[5] REVENUE BY REGION")
region_analysis = df_clean.groupby('region').agg(
    customers=('customer_id','nunique'),
    orders=('order_id','count'),
    revenue=('revenue','sum')
).reset_index()
region_analysis['revenue_share'] = (region_analysis['revenue'] / region_analysis['revenue'].sum() * 100).round(1)
region_analysis = region_analysis.sort_values('revenue', ascending=False)
print(region_analysis.to_string(index=False))

# ─────────────────────────────────────────────
# STEP 4: RFM CUSTOMER SEGMENTATION
# ─────────────────────────────────────────────

print("\n[6] RFM CUSTOMER SEGMENTATION")
analysis_date = df_clean['order_date'].max() + timedelta(days=1)

rfm = df_clean.groupby('customer_id').agg(
    last_order=('order_date','max'),
    frequency=('order_id','count'),
    monetary=('revenue','sum')
).reset_index()

rfm['recency'] = (analysis_date - rfm['last_order']).dt.days

# Score 1-5
rfm['r_score'] = pd.qcut(rfm['recency'], q=5, labels=[5,4,3,2,1]).astype(int)
rfm['f_score'] = pd.qcut(rfm['frequency'].rank(method='first'), q=5, labels=[1,2,3,4,5]).astype(int)
rfm['m_score'] = pd.qcut(rfm['monetary'], q=5, labels=[1,2,3,4,5]).astype(int)
rfm['rfm_score'] = rfm['r_score'] + rfm['f_score'] + rfm['m_score']

def segment(row):
    r, f, m = row['r_score'], row['f_score'], row['m_score']
    if r >= 4 and f >= 4 and m >= 4: return 'Champions'
    elif r >= 3 and f >= 3: return 'Loyal Customers'
    elif r >= 4 and f <= 2: return 'New Customers'
    elif r >= 3 and m >= 3: return 'Potential Loyalists'
    elif r <= 2 and f >= 3 and m >= 3: return 'At Risk'
    elif r <= 2 and f >= 4: return "Can't Lose Them"
    elif r <= 2 and f <= 2: return 'Lost Customers'
    else: return 'Average Customers'

rfm['segment'] = rfm.apply(segment, axis=1)

seg_summary = rfm.groupby('segment').agg(
    customers=('customer_id','count'),
    avg_revenue=('monetary','mean'),
    total_revenue=('monetary','sum')
).reset_index()
seg_summary['cust_pct'] = (seg_summary['customers'] / seg_summary['customers'].sum() * 100).round(1)
seg_summary['rev_pct'] = (seg_summary['total_revenue'] / seg_summary['total_revenue'].sum() * 100).round(1)
seg_summary = seg_summary.sort_values('total_revenue', ascending=False)
print(seg_summary[['segment','customers','cust_pct','avg_revenue','total_revenue','rev_pct']].to_string(index=False))

# ─────────────────────────────────────────────
# STEP 5: PARETO ANALYSIS — TOP 20% CUSTOMERS
# ─────────────────────────────────────────────

print("\n[7] PARETO ANALYSIS — TOP 20% vs BOTTOM 80%")
cust_rev = df_clean.groupby('customer_id')['revenue'].sum().reset_index()
cust_rev = cust_rev.sort_values('revenue', ascending=False)
cust_rev['cumulative_revenue'] = cust_rev['revenue'].cumsum()
cust_rev['cum_rev_pct'] = cust_rev['cumulative_revenue'] / cust_rev['revenue'].sum() * 100
cust_rev['customer_rank'] = range(1, len(cust_rev)+1)
cust_rev['customer_pct'] = cust_rev['customer_rank'] / len(cust_rev) * 100

top20 = cust_rev[cust_rev['customer_pct'] <= 20]
bottom80 = cust_rev[cust_rev['customer_pct'] > 20]

print(f"Top 20% Customers : {len(top20)} customers")
print(f"Revenue from Top 20%: ₹{top20['revenue'].sum():,.0f} ({top20['revenue'].sum()/cust_rev['revenue'].sum()*100:.1f}% of total)")
print(f"Bottom 80% Revenue  : ₹{bottom80['revenue'].sum():,.0f} ({bottom80['revenue'].sum()/cust_rev['revenue'].sum()*100:.1f}% of total)")
print(f"\n→ KEY INSIGHT: Top 20% of customers drive {top20['revenue'].sum()/cust_rev['revenue'].sum()*100:.0f}% of revenue")

# ─────────────────────────────────────────────
# STEP 6: EXPORT TO EXCEL
# ─────────────────────────────────────────────

with pd.ExcelWriter('/home/claude/Ecommerce_Analysis_Output.xlsx', engine='openpyxl') as writer:
    df_clean.drop(columns=['z_score']).to_excel(writer, sheet_name='Raw Data (Clean)', index=False)
    monthly.to_excel(writer, sheet_name='Monthly Revenue', index=False)
    cat_analysis.to_excel(writer, sheet_name='Category Analysis', index=False)
    region_analysis.to_excel(writer, sheet_name='Region Analysis', index=False)
    rfm.to_excel(writer, sheet_name='RFM Scores', index=False)
    seg_summary.to_excel(writer, sheet_name='Segment Summary', index=False)
    cust_rev.to_excel(writer, sheet_name='Pareto Analysis', index=False)

print("\n✓ Excel output saved: Ecommerce_Analysis_Output.xlsx")
print("\n[8] ANALYSIS COMPLETE")
