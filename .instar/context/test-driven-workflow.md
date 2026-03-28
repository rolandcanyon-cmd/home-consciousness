# Test-Driven Development Workflow

**Principle**: Write tests first, implement second, verify third.

## The Red-Green-Refactor Cycle

1. **🔴 Red**: Write a failing test that describes what you want to build
2. **🟢 Green**: Write the minimum code to make the test pass
3. **🔵 Refactor**: Clean up the code while keeping tests green

## BDD Test Template

```javascript
describe('ComponentName', function() {
  // Setup
  beforeEach(async function() {
    // Create test fixtures, initialize state
  });

  // Cleanup
  afterEach(async function() {
    // Clean up resources, delete temp files
  });

  describe('Feature Name', function() {
    it('Given [context], When [action], Then [outcome]', async function() {
      // Given: Set up initial conditions
      const initialState = setupTestState();

      // When: Perform the action being tested
      const result = await performAction(initialState);

      // Then: Assert expected outcomes
      expect(result).to.satisfy(expectedCondition);
    });
  });
});
```

## When to Write Tests

### Always Test
- New features or capabilities
- Bug fixes (write a test that reproduces the bug, then fix it)
- Public APIs and interfaces
- Critical business logic
- Anything that handles data persistence

### Unit Tests For
- Pure functions and business logic
- Data transformations
- Validation logic
- State management

### Integration Tests For
- External service interactions (HomeKit, APIs, databases)
- End-to-end workflows
- Network communication
- File system operations

## Running Tests During Development

```bash
# Run all tests
npm test

# Run specific test file
npm run test:registry
npm run test:homekit

# Watch mode (re-run on file changes)
npm run test:watch

# Run tests before committing
git add . && npm test && git commit -m "message"
```

## Test Organization

```
test/
├── unit/
│   ├── device-registry.test.js
│   └── ...
├── integration/
│   ├── homekit-adapter.integration.test.js
│   └── ...
├── e2e/
│   └── full-workflow.test.js
└── fixtures/
    └── sample-data.json
```

## Common Patterns

### Testing Async Operations
```javascript
it('Given async operation, When completed, Then result is correct', async function() {
  const result = await asyncOperation();
  expect(result).to.equal(expected);
});
```

### Testing Error Conditions
```javascript
it('Given invalid input, When processed, Then error is thrown', async function() {
  try {
    await operationWithInvalidInput();
    expect.fail('Should have thrown an error');
  } catch (err) {
    expect(err.message).to.include('expected error text');
  }
});
```

### Testing State Changes
```javascript
it('Given initial state, When action occurs, Then state updates correctly', async function() {
  const before = getState();
  await performAction();
  const after = getState();

  expect(after).to.not.deep.equal(before);
  expect(after.field).to.equal(expectedValue);
});
```

### Testing Persistence
```javascript
it('Given data saved, When reloaded, Then data persists', async function() {
  await saveData(testData);

  const newInstance = createNewInstance();
  await newInstance.load();

  expect(newInstance.getData()).to.deep.equal(testData);
});
```

## Assertions Cheat Sheet

```javascript
// Equality
expect(actual).to.equal(expected);
expect(actual).to.deep.equal(expected); // For objects/arrays

// Type checking
expect(value).to.be.a('string');
expect(value).to.be.an('object');
expect(value).to.be.an.instanceof(Class);

// Existence
expect(value).to.exist;
expect(value).to.be.undefined;
expect(value).to.be.null;

// Arrays
expect(array).to.be.an('array').that.is.empty;
expect(array).to.have.lengthOf(3);
expect(array).to.include(item);
expect(array).to.include.members([item1, item2]);

// Objects
expect(obj).to.have.property('key');
expect(obj).to.have.property('key', value);
expect(obj).to.have.all.keys('key1', 'key2');

// Numbers
expect(num).to.be.at.least(min);
expect(num).to.be.at.most(max);
expect(num).to.be.within(min, max);

// Booleans
expect(value).to.be.true;
expect(value).to.be.false;

// Strings
expect(str).to.match(/regex/);
expect(str).to.include('substring');
expect(str).to.have.lengthOf(10);
```

## Test Smells to Avoid

### ❌ Don't
```javascript
// Shared mutable state between tests
let sharedDevice;
beforeEach(() => {
  sharedDevice.update(); // BAD: modifies shared state
});

// Testing implementation details
expect(obj._internalCache).to.exist; // BAD: private field

// Tests that depend on execution order
it('test 1', () => { data.value = 1; });
it('test 2', () => { expect(data.value).to.equal(1); }); // BAD: depends on test 1

// Overly complex setup
beforeEach(() => {
  // 100 lines of setup
}); // BAD: hard to understand what's being tested
```

### ✅ Do
```javascript
// Fresh state for each test
beforeEach(() => {
  device = createNewDevice(); // GOOD: isolation
});

// Test public API only
expect(device.getStatus()).to.equal('ready'); // GOOD: public method

// Independent tests
it('test 1', () => {
  const data = { value: 1 };
  expect(data.value).to.equal(1);
}); // GOOD: self-contained

// Simple, focused setup
beforeEach(() => {
  state = createMinimalState(); // GOOD: only what's needed
});
```

## Debugging Failed Tests

1. **Read the error message carefully** - It tells you what failed and where
2. **Check the Given/When/Then** - Which step failed?
3. **Add console.logs** - See what values are actually being compared
4. **Run only that test** - Use `.only()`: `it.only('test', () => {})`
5. **Check test isolation** - Does the test pass when run alone?

## Quick Start for New Features

```bash
# 1. Create test file
touch test/my-feature.test.js

# 2. Write failing test
# (describe what you want to build)

# 3. Run test (should fail - RED)
npm test

# 4. Implement feature
# (minimum code to pass test)

# 5. Run test (should pass - GREEN)
npm test

# 6. Refactor
# (improve code, keep tests passing)

# 7. Commit
git add . && npm test && git commit -m "Add my-feature"
```

## Remember

> "Testing shows the presence, not the absence of bugs" - Dijkstra

Tests give you confidence, not certainty. But confidence is valuable:
- Refactor without fear
- Catch regressions early
- Document intended behavior
- Enable rapid iteration

**When in doubt, test it out.**
