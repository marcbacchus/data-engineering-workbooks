import pandas as pd
import numpy as np
import random
import os
import calendar
from datetime import datetime, timedelta
from faker import Faker

fake = Faker()
Faker.seed(42)
np.random.seed(42)
random.seed(42)

OUTPUT_DIR = "/mnt/user-data/outputs/ecommerce_dataset"
os.makedirs(OUTPUT_DIR, exist_ok=True)

START_TS = datetime(2019, 1, 1)
END_TS   = datetime(2023, 12, 31)

COUNTRIES = ['United States','United Kingdom','Canada','Australia','Germany',
             'France','Japan','Brazil','India','Mexico','Netherlands',
             'Spain','Italy','South Korea','Singapore']
COUNTRY_W = [0.35,0.10,0.08,0.07,0.06,0.05,0.05,0.04,0.04,0.03,
             0.02,0.02,0.02,0.02,0.05]
REGIONS = {
    'United States':'North America','Canada':'North America','Mexico':'North America',
    'United Kingdom':'Europe','Germany':'Europe','France':'Europe',
    'Netherlands':'Europe','Spain':'Europe','Italy':'Europe',
    'Japan':'Asia Pacific','Australia':'Asia Pacific',
    'South Korea':'Asia Pacific','Singapore':'Asia Pacific',
    'Brazil':'Latin America','India':'South Asia'
}
CATEGORIES = ['Electronics','Clothing','Home & Garden','Sports & Outdoors',
              'Books','Toys & Games','Beauty & Personal Care','Automotive',
              'Food & Grocery','Office Supplies']
CAT_W = [0.20,0.18,0.12,0.10,0.08,0.08,0.08,0.06,0.06,0.04]
SUBCATEGORIES = {
    'Electronics':['Smartphones','Laptops','Headphones','Cameras','Smart Home','Tablets','TVs'],
    'Clothing':['Mens Tops','Womens Tops','Jeans','Dresses','Footwear','Outerwear','Activewear'],
    'Home & Garden':['Furniture','Kitchen','Bedding','Garden Tools','Lighting','Storage','Decor'],
    'Sports & Outdoors':['Fitness Equipment','Camping','Cycling','Running','Team Sports','Water Sports'],
    'Books':['Fiction','Non-Fiction','Science and Tech','Business','Childrens','Education'],
    'Toys & Games':['Board Games','Action Figures','Puzzles','Educational','Outdoor Play','Video Games'],
    'Beauty & Personal Care':['Skincare','Hair Care','Makeup','Fragrance','Personal Hygiene','Vitamins'],
    'Automotive':['Car Electronics','Car Care','Interior Accessories','Tools','Exterior'],
    'Food & Grocery':['Snacks','Beverages','Organic','International Foods','Condiments'],
    'Office Supplies':['Stationery','Printers and Ink','Desk Accessories','Filing','Whiteboards']
}

def rand_timestamps_vectorized(n, year_p=[0.10,0.14,0.20,0.26,0.30], month_p=None):
    if month_p is None:
        month_p = [0.06,0.06,0.07,0.07,0.07,0.08,0.08,0.08,0.08,0.09,0.10,0.16]
    years  = np.random.choice([2019,2020,2021,2022,2023], n, p=year_p)
    months = np.random.choice(range(1,13), n, p=month_p)
    days   = np.array([random.randint(1, calendar.monthrange(y,m)[1])
                       for y,m in zip(years,months)])
    hours  = np.random.randint(0, 24, n)
    mins   = np.random.randint(0, 60, n)
    secs   = np.random.randint(0, 60, n)
    # build as strings directly — faster than datetime objects at scale
    return [f"{y:04d}-{mo:02d}-{d:02d} {h:02d}:{mi:02d}:{s:02d}"
            for y,mo,d,h,mi,s in zip(years,months,days,hours,mins,secs)]

# ── 1. SUPPLIERS ──────────────────────────────
print("[1/8] suppliers...")
N=1_000
df = pd.DataFrame({
    'supplier_id': range(1,N+1),
    'supplier_name': [fake.company() for _ in range(N)],
    'contact_name':  [fake.name() for _ in range(N)],
    'contact_email': [fake.company_email() for _ in range(N)],
    'phone':         [fake.phone_number() for _ in range(N)],
    'country':       np.random.choice(COUNTRIES,N,p=COUNTRY_W),
    'is_active':     np.random.choice([True,False],N,p=[0.92,0.08]),
    'created_at':    rand_timestamps_vectorized(N)
})
df['region'] = df['country'].map(REGIONS)
df.to_csv(f'{OUTPUT_DIR}/suppliers.csv', index=False)
print(f"   {len(df):,} rows")

# ── 2. PRODUCTS ───────────────────────────────
print("[2/8] products...")
N=10_000
cats  = np.random.choice(CATEGORIES, N, p=CAT_W)
subcats = [np.random.choice(SUBCATEGORIES[c]) for c in cats]
adj   = ['Premium','Classic','Essential','Pro','Elite','Standard','Value','Ultra','Smart','Eco']
nouns = ['Series','Edition','Collection','Model','Pack','Kit','Set','Line','Range','Bundle']
names = [f"{np.random.choice(adj)} {c.split()[0]} {np.random.choice(nouns)} {random.randint(100,9999)}"
         for c in cats]
prices = np.where(cats=='Electronics',
                  np.clip(np.random.lognormal(5.0,0.8,N), 9.99, 4999.99),
         np.where(np.isin(cats,['Books']),
                  np.clip(np.random.uniform(5,60,N), 4.99, 59.99),
                  np.clip(np.random.lognormal(3.8,0.7,N), 1.99, 999.99))).round(2)
df2 = pd.DataFrame({
    'product_id':   range(1,N+1),
    'product_name': names,
    'category':     cats,
    'subcategory':  subcats,
    'supplier_id':  np.random.randint(1,1001,N),
    'unit_price':   prices,
    'cost_price':   (prices * np.random.uniform(0.35,0.65,N)).round(2),
    'weight_kg':    np.random.uniform(0.1,25.0,N).round(2),
    'is_active':    np.random.choice([True,False],N,p=[0.88,0.12]),
    'created_at':   rand_timestamps_vectorized(N)
})
df2.to_csv(f'{OUTPUT_DIR}/products.csv', index=False)
print(f"   {len(df2):,} rows")

# ── 3. CUSTOMERS ──────────────────────────────
print("[3/8] customers...")
N=100_000
cust_countries = np.random.choice(COUNTRIES,N,p=COUNTRY_W)
df3 = pd.DataFrame({
    'customer_id':  range(1,N+1),
    'first_name':   [fake.first_name() for _ in range(N)],
    'last_name':    [fake.last_name() for _ in range(N)],
    'email':        [f"user{i}@{fake.free_email_domain()}" for i in range(N)],
    'phone':        [fake.phone_number() for _ in range(N)],
    'country':      cust_countries,
    'city':         [fake.city() for _ in range(N)],
    'postal_code':  [fake.postcode() for _ in range(N)],
    'segment':      np.random.choice(['consumer','business','enterprise'],N,p=[0.70,0.22,0.08]),
    'is_active':    np.random.choice([True,False],N,p=[0.85,0.15]),
    'created_at':   rand_timestamps_vectorized(N)
})
df3['region'] = df3['country'].map(REGIONS)
df3.to_csv(f'{OUTPUT_DIR}/customers.csv', index=False)
print(f"   {len(df3):,} rows")

# ── 4. ORDERS ─────────────────────────────────
print("[4/8] orders (2M)...")
N=2_000_000
ORDER_STATUSES = ['placed','confirmed','shipped','delivered','cancelled','returned']
ORDER_STATUS_W = [0.02,0.03,0.10,0.76,0.05,0.04]
PAYMENT_METHODS= ['credit_card','debit_card','paypal','apple_pay','google_pay','bank_transfer']
PAYMENT_W      = [0.40,0.20,0.18,0.10,0.08,0.04]
SHIPPING_METHODS=['standard','express','next_day','pickup']
SHIPPING_W     = [0.55,0.28,0.12,0.05]

ts_arr = rand_timestamps_vectorized(N)
statuses = np.random.choice(ORDER_STATUSES, N, p=ORDER_STATUS_W)
ship_countries = np.random.choice(COUNTRIES, N, p=COUNTRY_W)

# Vectorized shipping/delivery dates
ship_dates = np.where(
    np.isin(statuses, ['shipped','delivered','returned']),
    [t[:10] for t in ts_arr],  # placeholder, refined below
    None
)

df4 = pd.DataFrame({
    'order_id':         range(1,N+1),
    'customer_id':      np.random.randint(1,100_001,N),
    'order_status':     statuses,
    'payment_method':   np.random.choice(PAYMENT_METHODS,N,p=PAYMENT_W),
    'shipping_method':  np.random.choice(SHIPPING_METHODS,N,p=SHIPPING_W),
    'shipping_country': ship_countries,
    'order_total':      0.0,  # filled after order_items
    'created_at':       ts_arr
})
df4['shipping_region'] = df4['shipping_country'].map(REGIONS)

# Simple shipping/delivery offsets — vectorized
shipped_mask    = df4['order_status'].isin(['shipped','delivered','returned'])
delivered_mask  = df4['order_status'].isin(['delivered','returned'])

created_dates = pd.to_datetime(df4['created_at'])
ship_offset   = pd.to_timedelta(np.random.randint(1,6,N), unit='D')
deliv_offset  = pd.to_timedelta(np.random.randint(3,11,N), unit='D')

df4['shipping_date'] = None
df4['delivery_date'] = None
df4.loc[shipped_mask,  'shipping_date'] = (created_dates[shipped_mask]  + ship_offset[shipped_mask]).dt.strftime('%Y-%m-%d')
df4.loc[delivered_mask,'delivery_date'] = (created_dates[delivered_mask] + ship_offset[delivered_mask] + deliv_offset[delivered_mask]).dt.strftime('%Y-%m-%d')

df4.to_csv(f'{OUTPUT_DIR}/orders.csv', index=False)
print(f"   {len(df4):,} rows")

# ── 5. ORDER_ITEMS ────────────────────────────
print("[5/8] order_items (~5M)...")
ITEMS_PER_ORDER = np.random.choice([1,2,3,4,5,6], N, p=[0.35,0.28,0.18,0.10,0.06,0.03])
total_items = int(ITEMS_PER_ORDER.sum())

# Repeat order_ids by their item count
repeated_order_ids = np.repeat(np.arange(1, N+1), ITEMS_PER_ORDER)
n_items = len(repeated_order_ids)

prod_idx      = np.random.randint(0, 10_000, n_items)
unit_prices   = df2['unit_price'].values[prod_idx]
product_ids   = df2['product_id'].values[prod_idx]
quantities    = np.random.choice([1,2,3,4,5], n_items, p=[0.60,0.22,0.10,0.05,0.03])
discounts     = np.random.choice([0.0,0.05,0.10,0.15,0.20], n_items, p=[0.60,0.15,0.12,0.08,0.05])
line_totals   = (unit_prices * quantities * (1 - discounts)).round(2)

df5 = pd.DataFrame({
    'order_item_id': range(1, n_items+1),
    'order_id':      repeated_order_ids,
    'product_id':    product_ids,
    'quantity':      quantities,
    'unit_price':    unit_prices.round(2),
    'discount':      discounts,
    'line_total':    line_totals
})
df5.to_csv(f'{OUTPUT_DIR}/order_items.csv', index=False)
print(f"   {len(df5):,} rows")

# Patch order totals
order_totals = df5.groupby('order_id')['line_total'].sum().round(2)
df4['order_total'] = df4['order_id'].map(order_totals)
df4.to_csv(f'{OUTPUT_DIR}/orders.csv', index=False)
print(f"   orders.csv updated with order_total")

# ── 6. PRODUCT_REVIEWS ────────────────────────
print("[6/8] product_reviews (500K)...")
REVIEW_TEXT = {
    5:["Absolutely love this product! Exceeded all my expectations.",
       "Best purchase I have made this year. Highly recommend.",
       "Outstanding quality and fast shipping. Will buy again.",
       "Perfect in every way. Exactly as described and arrived early.",
       "Five stars. Fantastic quality and great value for money."],
    4:["Really good product overall. Minor issues but nothing major.",
       "Happy with my purchase. Good quality for the price.",
       "Works as expected. Delivery was quick and packaging was great.",
       "Solid product. Would recommend with a few small reservations.",
       "Great value for money. Not perfect but very close."],
    3:["Decent product but not quite what I expected from the description.",
       "Average quality. Does the job but nothing special.",
       "Mixed feelings. Some good aspects but a few disappointments.",
       "It is okay. Not bad but not great either.",
       "Meets basic requirements. Customer service could be better."],
    2:["Disappointed with the quality. Expected much better for this price.",
       "Had issues from day one. Not what was advertised at all.",
       "Packaging was damaged and product had defects on arrival.",
       "Would not buy again. Too many problems with this item.",
       "Below average. The description was misleading."],
    1:["Terrible product. Broke within a week of arrival.",
       "Complete waste of money. Nothing like the photos online.",
       "Avoid this product. Very poor quality and bad customer service.",
       "Returned immediately. Did not match description at all.",
       "Worst purchase ever. Would give zero stars if I could."]
}
N_REV = 500_000
delivered_orders = df4[df4['order_status']=='delivered'][['order_id','customer_id','delivery_date']].copy()
# sample from delivered order_items
delivered_items = df5[df5['order_id'].isin(delivered_orders['order_id'])].sample(
    n=min(N_REV, len(df5[df5['order_id'].isin(delivered_orders['order_id'])])),
    random_state=42
)
ratings = np.random.choice([1,2,3,4,5], len(delivered_items), p=[0.05,0.08,0.15,0.32,0.40])
rev_texts = [random.choice(REVIEW_TEXT[r]) for r in ratings]
rev_cust  = delivered_orders.set_index('order_id')['customer_id'].reindex(delivered_items['order_id'].values).values
rev_del   = delivered_orders.set_index('order_id')['delivery_date'].reindex(delivered_items['order_id'].values).values
df6 = pd.DataFrame({
    'review_id':     range(1, len(delivered_items)+1),
    'product_id':    delivered_items['product_id'].values,
    'customer_id':   rev_cust,
    'order_id':      delivered_items['order_id'].values,
    'rating':        ratings,
    'review_text':   rev_texts,
    'is_verified':   np.random.choice([True,False], len(delivered_items), p=[0.88,0.12]),
    'helpful_votes': np.random.poisson(3, len(delivered_items)),
    'created_at':    rand_timestamps_vectorized(len(delivered_items))
})
df6.to_csv(f'{OUTPUT_DIR}/product_reviews.csv', index=False)
print(f"   {len(df6):,} rows")

# ── 7. RETURNS ────────────────────────────────
print("[7/8] returns (~80K)...")
RETURN_REASONS = ['Defective or damaged','Not as described','Wrong item received',
                  'Changed my mind','Better price found elsewhere',
                  'Item no longer needed','Arrived too late','Quality not as expected']
RETURN_R_W     = [0.22,0.18,0.12,0.18,0.08,0.10,0.07,0.05]
ret_order_ids  = df4[df4['order_status']=='returned']['order_id'].values
ret_items      = df5[df5['order_id'].isin(ret_order_ids)].sample(
    n=min(80_000, len(df5[df5['order_id'].isin(ret_order_ids)])), random_state=42)
ret_cust = df4.set_index('order_id')['customer_id'].reindex(ret_items['order_id'].values).values
df7 = pd.DataFrame({
    'return_id':      range(1, len(ret_items)+1),
    'order_id':       ret_items['order_id'].values,
    'order_item_id':  ret_items['order_item_id'].values,
    'product_id':     ret_items['product_id'].values,
    'customer_id':    ret_cust,
    'return_reason':  np.random.choice(RETURN_REASONS, len(ret_items), p=RETURN_R_W),
    'return_status':  np.random.choice(['requested','approved','received','refunded','rejected'],
                                        len(ret_items), p=[0.05,0.10,0.15,0.65,0.05]),
    'refund_amount':  (ret_items['line_total'].values * np.random.uniform(0.85,1.0,len(ret_items))).round(2),
    'created_at':     rand_timestamps_vectorized(len(ret_items))
})
df7.to_csv(f'{OUTPUT_DIR}/returns.csv', index=False)
print(f"   {len(df7):,} rows")

# ── 8. CLICKSTREAM_EVENTS ─────────────────────
print("[8/8] clickstream_events (3M)...")
N=3_000_000
EVENTS   = ['page_view','product_view','add_to_cart','remove_from_cart',
            'checkout_start','purchase','search','wishlist_add']
EVENT_W  = [0.35,0.25,0.15,0.05,0.06,0.04,0.08,0.02]
DEVICES  = ['desktop','mobile','tablet'];  DEV_W=[0.45,0.42,0.13]
BROWSERS = ['Chrome','Safari','Firefox','Edge','Samsung Internet']; BROW_W=[0.52,0.28,0.08,0.07,0.05]
OS_LIST  = ['Windows','macOS','iOS','Android','Linux']; OS_W=[0.35,0.18,0.22,0.20,0.05]

event_types  = np.random.choice(EVENTS, N, p=EVENT_W)
prod_mask    = np.isin(event_types, ['product_view','add_to_cart','wishlist_add','remove_from_cart'])
prod_ids_cs  = np.where(prod_mask, np.random.randint(1,10_001,N), 0)

# ~17% anonymous sessions (customer_id = null)
cust_ids_cs  = np.random.randint(1, 100_001, N).astype(object)
anon_mask    = np.random.random(N) < 0.17
cust_ids_cs[anon_mask] = None

session_ids  = [f"s{i:09d}" for i in np.random.randint(0, N//3, N)]

df8 = pd.DataFrame({
    'event_id':                range(1, N+1),
    'session_id':              session_ids,
    'customer_id':             cust_ids_cs,
    'event_type':              event_types,
    'product_id':              np.where(prod_mask, prod_ids_cs, None),
    'device_type':             np.random.choice(DEVICES, N, p=DEV_W),
    'browser':                 np.random.choice(BROWSERS, N, p=BROW_W),
    'operating_system':        np.random.choice(OS_LIST, N, p=OS_W),
    'session_duration_seconds':np.clip(np.random.exponential(180,N).astype(int),1,3600),
    'created_at':              rand_timestamps_vectorized(N)
})
df8.to_csv(f'{OUTPUT_DIR}/clickstream_events.csv', index=False)
print(f"   {len(df8):,} rows")

# ── SUMMARY ───────────────────────────────────
import glob
print("\n" + "="*55)
print("COMPLETE")
print("="*55)
tables = [('suppliers.csv',df),('products.csv',df2),('customers.csv',df3),
          ('orders.csv',df4),('order_items.csv',df5),('product_reviews.csv',df6),
          ('returns.csv',df7),('clickstream_events.csv',df8)]
total_rows=0
for fname, d in tables:
    mb = os.path.getsize(f'{OUTPUT_DIR}/{fname}')/(1024*1024)
    print(f"  {fname:<30} {len(d):>10,} rows  {mb:>6.1f} MB")
    total_rows += len(d)
total_mb = sum(os.path.getsize(f) for f in glob.glob(f'{OUTPUT_DIR}/*.csv'))/(1024*1024)
print(f"  {'TOTAL':<30} {total_rows:>10,} rows  {total_mb:>6.1f} MB")
