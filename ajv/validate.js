// ajv/validate.js

const fs = require('fs');
const Ajv = require('ajv');

// Get file paths from command-line arguments
const schemaPath = process.argv[2];
const dataPath = process.argv[3];

if (!schemaPath || !dataPath) {
  console.error('Usage: node validate.js <path_to_schema.json> <path_to_data.json>');
  process.exit(1);
}

try {
  // Read and parse the JSON files
  const schema = JSON.parse(fs.readFileSync(schemaPath, 'utf8'));
  const data = JSON.parse(fs.readFileSync(dataPath, 'utf8'));

  // Validate
  const ajv = new Ajv({ strict: false });
  const validate = ajv.compile(schema);
  const valid = validate(data);

  if (valid) {
    console.log('✅ Data is valid!');
  } else {
    console.error('❌ Data is invalid:');
    console.error(validate.errors);
    process.exit(1); // <-- ADD THIS LINE
  }
} catch (e) {
  console.error('An error occurred:', e.message);
  process.exit(1); // It's also good practice to have this in the catch block
}
