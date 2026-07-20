-- Register 'aia_contract' in the document_template_type enum so the app can
-- create AIA Contract (A101/A102) documents and seed a default template row
-- of that type. AIA Contracts are a customer-invoice-category document type
-- that sits alongside the existing 'aia_pay_app' (G702/G703) type.
ALTER TYPE document_template_type ADD VALUE IF NOT EXISTS 'aia_contract';
