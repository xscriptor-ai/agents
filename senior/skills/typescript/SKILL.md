---
description: "Deep TypeScript patterns for advanced type system usage, module resolution, and build configuration"
---

# TypeScript

## Advanced Type System

### Conditional Types
```typescript
type IsString<T> = T extends string ? true : false;

type ExtractProps<T, K> = K extends keyof T ? T[K] : never;

type FunctionReturnType<T> = T extends (...args: any[]) => infer R ? R : never;
```

### Mapped Types
```typescript
type Readonly<T> = { readonly [K in keyof T]: T[K] };

type Partial<T> = { [K in keyof T]?: T[K] };

type Pick<T, K extends keyof T> = { [P in K]: T[P] };

type Record<K extends keyof any, V> = { [P in K]: V };
```

### Template Literal Types
```typescript
type EventName<T extends string> = `on${Capitalize<T>}`;
type ApiPath<Resource extends string> = `/api/v1/${Resource}`;

type PropEventSource<T> = {
  on<K extends string & keyof T>(event: `change${Capitalize<K>}`, fn: (v: T[K]) => void): void;
};
```

### Infer Pattern
```typescript
type UnwrapPromise<T> = T extends Promise<infer U> ? U : T;
type UnwrapArray<T> = T extends Array<infer U> ? U : T;

type DeepUnwrap<T> = T extends Promise<infer U> ? DeepUnwrap<U> : T;
```

## Discriminated Unions
```typescript
type Shape =
  | { kind: "circle"; radius: number }
  | { kind: "rect"; width: number; height: number }
  | { kind: "triangle"; base: number; height: number };

function area(s: Shape): number {
  switch (s.kind) {
    case "circle": return Math.PI * s.radius ** 2;
    case "rect": return s.width * s.height;
    case "triangle": return (s.base * s.height) / 2;
  }
}
```

## Branded Types
```typescript
type Brand<T, B> = T & { __brand: B };
type UserId = Brand<string, "UserId">;
type Email = Brand<string, "Email">;

function createUser(id: UserId, email: Email) { }

const uid = "abc" as UserId;
const em = "a@b.com" as Email;
createUser(uid, em);
```

## Type Guards
```typescript
function isError(e: unknown): e is Error {
  return e instanceof Error && typeof e.message === "string";
}

function assertNonNull<T>(v: T | null): asserts v is T {
  if (v === null) throw new Error("Unexpected null");
}
```

## Module Resolution & ESM/CJS Interop

- Use `"moduleResolution": "bundler"` with modern bundlers (Vite, esbuild, webpack).
- For Node: `"moduleResolution": "node16"` or `"nodenext"`.
- ESM: `"type": "module"` in package.json. Use `.js` extensions in imports.
- CJS interop: `"esModuleInterop": true` + `"allowSyntheticDefaultImports": true`.
- Path aliases: `"paths": { "@/*": ["./src/*"] }` with `"baseUrl": "."`.

## tsconfig Optimization

```jsonc
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ESNext",
    "moduleResolution": "bundler",
    "strict": true,
    "noUncheckedIndexedAccess": true,
    "exactOptionalPropertyTypes": true,
    "forceConsistentCasingInFileNames": true,
    "isolatedModules": true,
    "skipLibCheck": true,
    "declaration": true,
    "declarationMap": true,
    "sourceMap": true,
    "outDir": "dist"
  },
  "include": ["src"],
  "exclude": ["node_modules", "dist"]
}
```

## Declaration Files
```typescript
// globals.d.ts
declare module "*.module.css" {
  const classes: { [key: string]: string };
  export default classes;
}

declare module "*.svg" {
  const content: React.FC<React.SVGProps<SVGSVGElement>>;
  export default content;
}
```

## Project Structure
```
src/
  types/         # Shared type definitions
  lib/           # Pure utility modules
  features/      # Feature modules
  app/           # Application entry
  __tests__/     # Unit tests
dist/            # Compiled output
```
