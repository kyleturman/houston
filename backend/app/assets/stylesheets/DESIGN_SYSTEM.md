# Houston Admin Design System

A dark-mode-only design system for Houston's admin dashboard, sign-in, and setup wizard flows.

## Philosophy

- **Dark mode only**: All backgrounds are shades of black for a sleek, modern interface
- **No shadows**: Prefer subtle borders for depth and separation
- **Monospace body**: Geist Mono for technical, code-like feel
- **Clean typography**: Space Grotesk for titles, clean hierarchy
- **Minimal color palette**: Accent blue, tertiary purple, success green, error red

## Color Palette

### Backgrounds
- `--color-bg-primary`: #000000 (Main background)
- `--color-bg-secondary`: #0a0a0a (Slightly elevated)
- `--color-bg-tertiary`: #141414 (Cards, inputs)
- `--color-bg-elevated`: #1a1a1a (Highest elevation)

### Text
- `--color-text-primary`: #ffffff (Primary text)
- `--color-text-secondary`: #e5e5e5 (Secondary text)
- `--color-text-tertiary`: #a3a3a3 (Labels, meta)
- `--color-text-muted`: #737373 (Disabled, placeholders)

### Accent Colors
- `--color-accent`: #6B90FF (Primary accent blue)
- `--color-accent-hover`: #5880ee (Hover state)
- `--color-accent-muted`: rgba(107, 144, 255, 0.1) (Backgrounds)

### Semantic Colors
- `--color-tertiary`: #E4B2FA (Tertiary accent, seldom used)
- `--color-success`: #45E38F (Success states)
- `--color-error`: #FE5B5B (Error states)

### Borders
- `--color-border-subtle`: #262626 (Subtle borders)
- `--color-border-medium`: #404040 (Medium borders)

## Typography

### Fonts
- **Titles**: `var(--font-title)` = Space Grotesk
- **Body**: `var(--font-body)` = Geist Mono

### Type Scale
```css
.text-title       /* 32px, titles */
.text-title-sm    /* 24px, section headings */
.text-body        /* 14px, body text */
.text-body-sm     /* 12px, small text, labels */
```

## Components

### Buttons
```html
<!-- Primary button (white with black text) -->
<button class="btn-primary">Primary Action</button>

<!-- Secondary button (transparent with border) -->
<button class="btn-secondary">Secondary Action</button>

<!-- Accent button (blue) -->
<button class="btn-accent">Accent Action</button>

<!-- Success button (green) -->
<button class="btn-success">Success Action</button>

<!-- Error button (red) -->
<button class="btn-error">Delete</button>
```

### Form Elements
```html
<!-- Input field -->
<label class="form-label">Email Address</label>
<input type="email" class="input-field" placeholder="user@example.com">

<!-- Select field -->
<select class="input-field">
  <option>Option 1</option>
</select>
```

### Cards
```html
<!-- Basic card -->
<div class="card">
  <h3 class="text-body mb-3" style="font-weight: 600;">Card Title</h3>
  <p class="text-body-sm text-muted">Card content goes here</p>
</div>

<!-- Stat card -->
<div class="stat-card">
  <p class="stat-label">Label</p>
  <p class="stat-value">1,234</p>
</div>
```

### Alerts
```html
<!-- Success alert -->
<div class="alert-success">
  <p class="text-body">Success message</p>
</div>

<!-- Error alert -->
<div class="alert-error">
  <p class="text-body">Error message</p>
</div>

<!-- Info alert -->
<div class="alert-info">
  <p class="text-body">Info message</p>
</div>
```

### Tables
```html
<div class="table-container">
  <table class="table">
    <thead>
      <tr>
        <th>Column 1</th>
        <th>Column 2</th>
      </tr>
    </thead>
    <tbody>
      <tr>
        <td>Data 1</td>
        <td>Data 2</td>
      </tr>
    </tbody>
  </table>
</div>
```

### Status Indicators
```html
<span class="status-dot status-healthy"></span>
<span class="status-dot status-unhealthy"></span>
```

## Layout

### Container
```html
<div class="container">
  <!-- Content constrained to 1280px max-width with padding -->
</div>
```

### Grid Utilities
```html
<!-- 2 column grid -->
<div class="grid-2">
  <div>Column 1</div>
  <div>Column 2</div>
</div>

<!-- 3 column grid -->
<div class="grid-3">
  <div>Column 1</div>
  <div>Column 2</div>
  <div>Column 3</div>
</div>

<!-- 4 column grid -->
<div class="grid-4">
  <div>Column 1</div>
  <div>Column 2</div>
  <div>Column 3</div>
  <div>Column 4</div>
</div>
```

Note: Grids automatically collapse to 1 column on mobile (< 768px).

## Spacing

Use CSS variables for consistent spacing:

```css
--space-1: 0.25rem;   /* 4px */
--space-2: 0.5rem;    /* 8px */
--space-3: 0.75rem;   /* 12px */
--space-4: 1rem;      /* 16px */
--space-6: 1.5rem;    /* 24px */
--space-8: 2rem;      /* 32px */
--space-12: 3rem;     /* 48px */
```

### Spacing Utility Classes
```html
<!-- Margin bottom -->
<div class="mb-1">...</div>  <!-- 4px -->
<div class="mb-2">...</div>  <!-- 8px -->
<div class="mb-4">...</div>  <!-- 16px -->
<div class="mb-6">...</div>  <!-- 24px -->
<div class="mb-8">...</div>  <!-- 32px -->

<!-- Margin top -->
<div class="mt-1">...</div>
<div class="mt-2">...</div>
<!-- etc. -->
```

## Utility Classes

### Colors
```css
.text-accent           /* Blue accent color */
.text-success          /* Green success color */
.text-error            /* Red error color */
.text-tertiary-accent  /* Purple tertiary color */
.text-muted            /* Muted gray color */
```

### Borders
```css
.border-subtle         /* Subtle 1px border */
.border-medium         /* Medium 1px border */
```

### Flexbox
```css
.flex                  /* display: flex */
.flex-col              /* flex-direction: column */
.items-center          /* align-items: center */
.justify-between       /* justify-content: space-between */
.justify-center        /* justify-content: center */
.gap-2                 /* gap: 0.5rem */
.gap-3                 /* gap: 0.75rem */
.gap-4                 /* gap: 1rem */
```

## Best Practices

1. **Use semantic colors**: Don't use `--color-success` for non-success states
2. **Consistent spacing**: Always use spacing variables, never hardcode pixels
3. **Typography hierarchy**: Use the type scale consistently (title > title-sm > body > body-sm)
4. **Buttons**: Primary for main actions, accent for important secondary actions
5. **Forms**: Always pair inputs with labels using `.form-label`
6. **Cards**: Use `.card` for general content, `.stat-card` for metrics
7. **Borders over shadows**: Prefer `border-subtle` or `border-medium` for depth

## Examples

### Sign-in Form
```html
<div class="card">
  <h2 class="text-title mb-3">Sign In</h2>
  <p class="text-body text-muted mb-6">Enter your email</p>

  <form class="flex flex-col gap-4">
    <div>
      <label class="form-label">Email Address</label>
      <input type="email" class="input-field" placeholder="admin@example.com">
    </div>

    <button type="submit" class="btn-primary" style="width: 100%;">
      Send Magic Link
    </button>
  </form>
</div>
```

### Stats Grid
```html
<div class="grid-3 mb-6">
  <div class="stat-card">
    <p class="stat-label">Total Users</p>
    <p class="stat-value">1,234</p>
  </div>

  <div class="stat-card">
    <p class="stat-label">Active</p>
    <p class="stat-value text-success">856</p>
  </div>

  <div class="stat-card">
    <p class="stat-label">Errors</p>
    <p class="stat-value text-error">12</p>
  </div>
</div>
```

## Integration

The design system is automatically loaded in the admin layout:

```erb
<%= stylesheet_link_tag "admin_design_system", "data-turbo-track": "reload" %>
```

Fonts are loaded from Google Fonts:
- Space Grotesk (titles)
- Geist Mono (body)
