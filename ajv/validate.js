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
  const ajv = new Ajv(
    { strict: false,
      allErrors: true,
      verbose: true
    });
  const validate = ajv.compile(schema);
  const valid = validate(data);

  if (valid) {
    console.error('✅ Data is valid!');
  } else {
    console.error('❌ Data is invalid:');
    console.error("DATA")
    console.error(data)
    console.error("ERRORS")
    console.error(validate.errors)
    console.error("ERROR REPORT")

    // Group all error objects by their instance path
    const errorsByPath = validate.errors.reduce((acc, err) => {
      const path = err.instancePath || '(root of JSON)';
      if (!acc[path]) {
        acc[path] = [];
      }
      acc[path].push(err);
      return acc;
    }, {});

    for (const path in errorsByPath) {
      console.error(`  - At instance path: ${path}`);
      let errors = errorsByPath[path];

      // 1. Filter out the summary 'anyOf' message if more specific errors exist
      if (errors.length > 1) {
        errors = errors.filter(err => err.keyword !== 'anyOf');
      }

      // 2. Consolidate 'type' errors into a single, more readable message
      const typeErrors = errors.filter(err => err.keyword === 'type');
      if (typeErrors.length > 1) {
        // Get all unique types from the 'type' errors
        const uniqueTypes = [...new Set(typeErrors.map(err => err.params.type))];
        console.error(`    - Value must be one of the following types: ${uniqueTypes.join(', ')}`);
        // Remove the individual type errors so they aren't processed again
        errors = errors.filter(err => err.keyword !== 'type');
      }

      // 3. Process the remaining errors, with special handling for 'enum'
      errors.forEach(err => {
        switch (err.keyword) {
          case 'enum':
            // For enum errors, list the allowed values
            const allowed = err.params.allowedValues.join(', ');
            console.error(`    - Must be one of the following values: [${allowed}]`);
            break;
          default:
            // Fallback for all other errors
            console.error(`    - ${err.message}`);
            break;
        }
      });
    }
    process.exit(1);
  }
} catch (e) {
  console.error('An error occurred:', e.message);
  process.exit(1); // It's also good practice to have this in the catch block
}
